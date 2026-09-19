import Foundation

/// Validated 16-bit little-endian PCM WAV. No files or microphone access.
public struct PCMRecording: Sendable {
    public let sampleRate: Double
    public let samples: [Float]

    public init(wav: Data) throws {
        guard wav.count <= 120 * 96_000 * 4 + 4096 else { throw RecognitionError.invalidAudio }
        let data = Array(wav)
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        func tag(_ offset: Int) -> String { String(decoding: data[offset..<offset + 4], as: UTF8.self) }
        guard data.count >= 44, tag(0) == "RIFF", tag(8) == "WAVE", u32(4) == data.count - 8 else {
            throw RecognitionError.invalidAudio
        }
        var offset = 12
        var format: (rate: Int, channels: Int)?
        var audio: Range<Int>?
        while offset + 8 <= data.count {
            let count = u32(offset + 4)
            let start = offset + 8
            guard count <= data.count - start else { throw RecognitionError.invalidAudio }
            if tag(offset) == "fmt " {
                guard format == nil, count >= 16, u16(start) == 1,
                      (1...2).contains(u16(start + 2)), u16(start + 14) == 16,
                      (8_000...96_000).contains(u32(start + 4)),
                      u16(start + 12) == u16(start + 2) * 2,
                      u32(start + 8) == u32(start + 4) * u16(start + 12) else { throw RecognitionError.invalidAudio }
                format = (u32(start + 4), u16(start + 2))
            } else if tag(offset) == "data" {
                guard audio == nil else { throw RecognitionError.invalidAudio }
                audio = start..<start + count
            }
            offset = start + count + count % 2
        }
        guard let format, let audio, !audio.isEmpty,
              audio.count % (format.channels * 2) == 0,
              audio.count / (format.channels * 2) <= format.rate * 120 else { throw RecognitionError.invalidAudio }
        sampleRate = Double(format.rate)
        samples = stride(from: audio.lowerBound, to: audio.upperBound, by: format.channels * 2).map { index in
            var value: Float = 0
            for channel in 0..<format.channels {
                value += Float(Int16(bitPattern: UInt16(u16(index + channel * 2)))) / 32768
            }
            return value / Float(format.channels)
        }
    }
}
