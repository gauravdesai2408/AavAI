import AVFoundation
import Speech
import Foundation

/// Native feasibility adapter. Installation is separate and explicit; recognition
/// never initiates an asset download or falls back to network recognition.
@available(macOS 26, iOS 26, *)
public struct AppleFileRecognizer: Sendable {
    public init() {}
    public func availability(locale: String) async -> String {
        guard let module = try? await transcriber(locale: locale) else { return "unavailable" }
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return "installed"
        default: return "assets-not-installed"
        }
    }
    public func installAssets(locale: String) async throws {
        let module = try await transcriber(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    public func transcribe(file: URL, locale: String, dictionary: [String]) async throws -> String {
        try Task.checkCancellation()
        let module = try await transcriber(locale: locale)
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw RecognitionError.assetsNotInstalled
        }
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(dictionary.prefix(100)).map { String($0.prefix(100)) }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.setContext(context)
        return try await withTaskCancellationHandler {
            let results = Task {
                var text: [String] = []
                for try await result in module.results {
                    try Task.checkCancellation()
                    if result.isFinal { text.append(String(result.text.characters)) }
                }
                return text.joined(separator: " ")
            }
            do {
                try Task.checkCancellation()
                let audio = try AVAudioFile(forReading: file)
                try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
                let text = try await results.value
                try Task.checkCancellation()
                await analyzer.cancelAndFinishNow()
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// In-memory capture path: no temporary audio file is created. Input is
    /// consumed in one-second chunks with backpressure from the analyzer.
    public func transcribe(wav: Data, locale: String, dictionary: [String]) async throws -> String {
        try Task.checkCancellation()
        let recording = try PCMRecording(wav: wav)
        let module = try await transcriber(locale: locale)
        guard await AssetInventory.status(forModules: [module]) == .installed else { throw RecognitionError.assetsNotInstalled }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw RecognitionError.invalidAudio
        }
        let source = try RecordingInput(recording: recording, output: format)
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(dictionary.prefix(100)).map { String($0.prefix(100)) }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.setContext(context)
        let stream = AsyncThrowingStream<AnalyzerInput, Error>(unfolding: { try await source.next() })
        return try await withTaskCancellationHandler {
            let results = Task {
                var text: [String] = []
                for try await result in module.results {
                    try Task.checkCancellation()
                    if result.isFinal { text.append(String(result.text.characters)) }
                }
                return text.joined(separator: " ")
            }
            do {
                try Task.checkCancellation()
                try await analyzer.start(inputSequence: stream)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let text = try await results.value
                try Task.checkCancellation()
                await analyzer.cancelAndFinishNow()
                return text
            } catch {
                results.cancel(); await analyzer.cancelAndFinishNow(); throw error
            }
        } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
    }

    private func transcriber(locale: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            throw RecognitionError.unavailable
        }
        return SpeechTranscriber(locale: supported, preset: .transcription)
    }
}

@available(macOS 26, iOS 26, *)
private actor RecordingInput {
    private let recording: PCMRecording
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private var position = 0

    init(recording: PCMRecording, output: AVAudioFormat) throws {
        guard let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: recording.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output) else { throw RecognitionError.invalidAudio }
        self.recording = recording; inputFormat = input; outputFormat = output; self.converter = converter
    }

    func next() throws -> AnalyzerInput? {
        try Task.checkCancellation()
        let remaining = recording.samples.count - position
        // Drain the resampler at end of input; do not discard its trailing frames.
        let count = min(Int(recording.sampleRate), remaining)
        let capacity = AVAudioFrameCount(ceil(Double(max(count, 1)) * outputFormat.sampleRate / recording.sampleRate) + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { throw RecognitionError.invalidAudio }
        var input: AVAudioPCMBuffer?
        if count > 0 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else { throw RecognitionError.invalidAudio }
            buffer.frameLength = AVAudioFrameCount(count)
            for index in 0..<count { channel[index] = recording.samples[position + index] }
            input = buffer; position += count
        }
        let feed = ConverterInput(buffer: input, endOfStream: count == 0)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            feed.next(status: inputStatus)
        }
        if let error { throw error }
        guard status != .error else { throw RecognitionError.invalidAudio }
        if output.frameLength > 0 { return AnalyzerInput(buffer: output) }
        if count == 0 { return nil }
        return try next()
    }
}

/// AVAudioConverter's synchronous callback is annotated Sendable. The buffer is
/// filled before publication, returned once, and never mutated by this holder.
private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer?
    private let endOfStream: Bool
    private var supplied = false
    init(buffer: AVAudioPCMBuffer?, endOfStream: Bool) { self.buffer = buffer; self.endOfStream = endOfStream }
    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        lock.withLock {
            if let buffer, !supplied { supplied = true; status.pointee = .haveData; return buffer }
            status.pointee = endOfStream ? .endOfStream : .noDataNow
            return nil
        }
    }
}
