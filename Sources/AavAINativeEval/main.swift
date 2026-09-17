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
        case "transcribe" where args.count == 2:
            let start = ContinuousClock.now
            let raw = try await recognizer.transcribe(file: URL(fileURLWithPath: args[1]), locale: "en-US", dictionary: [])
            let duration = start.duration(to: .now).components
            let result = EvaluationResult(engine: "apple-speechtranscriber", raw: raw,
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
        let raw: String
        let formatted: String
        /// End-to-end file evaluation, NOT microphone release-to-insertion latency.
        let elapsedMilliseconds: Double
    }
}
