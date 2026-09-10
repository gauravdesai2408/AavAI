import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class MicrophoneCapture: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var bytes = Data()
    private var recording = false
    private var sampleRate: UInt32 = 48_000
    private var speechFrames = 0
    private var configurationObserver: NSObjectProtocol?
    private var deviceChanged = false

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.lock.withLock {
                if self?.recording == true { self?.deviceChanged = true }
            }
        }
    }

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw DictationFailure.permissionDenied("Microphone")
        }
        lock.withLock {
            bytes.removeAll(keepingCapacity: true)
            speechFrames = 0
            deviceChanged = false
            recording = false
        }
        let input = engine.inputNode
        if var selectedDevice = await MainActor.run(body: { AudioDeviceManager.shared.selectedDeviceID }),
           let audioUnit = input.audioUnit {
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &selectedDevice,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { throw DictationFailure.transcription("The selected microphone is unavailable") }
        }
        let format = input.outputFormat(forBus: 0)
        sampleRate = UInt32(format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?.pointee else { return }
            let frames = Int(buffer.frameLength)
            var pcm = Data(capacity: frames * 2)
            var energy: Float = 0
            for index in 0..<frames {
                let value = max(-1, min(1, channel[index]))
                energy += value * value
                var sample = Int16(value * Float(Int16.max)).littleEndian
                withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
            }
            let rms = frames > 0 ? sqrt(energy / Float(frames)) : 0
            self.lock.withLock {
                if self.recording {
                    self.bytes.append(pcm)
                    // Loudness is not a speech classifier. Preserve quiet input
                    // for recognition instead of rejecting whispers at -50 dBFS.
                    if rms > 0.0001 { self.speechFrames += frames }
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
            lock.withLock { recording = true }
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() async throws -> Data {
        let result: (Data, UInt32, Int, Bool) = lock.withLock {
            recording = false
            return (bytes, sampleRate, speechFrames, deviceChanged)
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        if result.3 { throw DictationFailure.audioDeviceChanged }
        if result.2 < Int(Double(result.1) * 0.08) { throw DictationFailure.noAudio }
        return Self.wavData(pcm: Self.normalizeQuietPCM(result.0), sampleRate: result.1)
    }

    func cancel() async {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.withLock { recording = false; bytes.removeAll() }
    }

    /// Apply a single bounded gain, preserving timing and avoiding clipping.
    /// This boosts quiet recordings; it does not distinguish speech from noise.
    static func normalizeQuietPCM(_ pcm: Data) -> Data {
        guard pcm.count >= 2 else { return pcm }
        let samples: [Int16] = stride(from: 0, to: pcm.count - 1, by: 2).map { index in
            Int16(bitPattern: UInt16(pcm[index]) | UInt16(pcm[index + 1]) << 8)
        }
        let peak = samples.map { abs(Double($0)) }.max() ?? 0
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        guard rms > 3, peak > 0 else { return pcm }
        let gain = min(12, min(1_300 / rms, 29_490 / peak))
        guard gain > 1 else { return pcm }
        var output = Data(capacity: pcm.count)
        for sample in samples {
            var amplified = Int16((Double(sample) * gain).rounded()).littleEndian
            withUnsafeBytes(of: &amplified) { output.append(contentsOf: $0) }
        }
        return output
    }

    private static func wavData(pcm: Data, sampleRate: UInt32) -> Data {
        var output = Data()
        func append<T>(_ value: T) { var little = value; withUnsafeBytes(of: &little) { output.append(contentsOf: $0) } }
        output.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count).littleEndian)
        output.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16).littleEndian); append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian); append((sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        output.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count).littleEndian); output.append(pcm)
        return output
    }
}
