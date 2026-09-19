import AavAICore
import Foundation

@main
struct NativeEvaluation {
    static func main() async throws {
        guard #available(macOS 26, iOS 26, *) else {
            throw EvaluationError.unsupportedOS
        }
        let args = Array(CommandLine.arguments.dropFirst())
        let recognizer = AppleFileRecognizer()
        switch args.first {
        case "status":
            print(await recognizer.availability(locale: "en-US"))
        case "install-assets":
            try await recognizer.installAssets(locale: "en-US")
            print(await recognizer.availability(locale: "en-US"))
        case "transcribe" where args.count == 2, "transcribe-memory" where args.count == 2:
            let start = ContinuousClock.now
            let url = URL(fileURLWithPath: args[1])
            let raw: String
            let inputPath: String
            if args[0] == "transcribe-memory" {
                // Exercise the same bounded PCM/resampling path as Mac dictation.
                // Never load an arbitrarily large recording into process memory.
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let maximumBytes = 120 * 96_000 * 4 + 4096
                let wav = try file.read(upToCount: maximumBytes + 1) ?? Data()
                guard wav.count <= maximumBytes else { throw RecognitionError.invalidAudio }
                raw = try await recognizer.transcribe(wav: wav, locale: "en-US", dictionary: [])
                inputPath = "bounded-memory-pcm"
            } else {
                raw = try await recognizer.transcribe(file: url, locale: "en-US", dictionary: [])
                inputPath = "file"
            }
            let duration = start.duration(to: .now).components
            let result = EvaluationResult(engine: "apple-speechtranscriber", inputPath: inputPath, raw: raw,
                formatted: ConservativeFormatter().format(raw),
                elapsedMilliseconds: Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        default:
            throw EvaluationError.usage
        }
    }
    enum EvaluationError: Error { case unsupportedOS, usage }
    struct EvaluationResult: Encodable {
        let engine: String
        let inputPath: String
        let raw: String
        let formatted: String
        /// End-to-end file evaluation, NOT microphone release-to-insertion latency.
        let elapsedMilliseconds: Double
    }
}
