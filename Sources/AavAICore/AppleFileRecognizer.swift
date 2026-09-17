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

    private func transcriber(locale: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            throw RecognitionError.unavailable
        }
        return SpeechTranscriber(locale: supported, preset: .transcription)
    }
}
