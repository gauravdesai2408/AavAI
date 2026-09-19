import Foundation
import AavAICore

enum InferenceSelection {
    static var usesNativeApple: Bool {
        ProcessInfo.processInfo.environment["AAVAI_ENGINE"] == "apple"
            || Bundle.main.object(forInfoDictionaryKey: "AavAIEngine") as? String == "apple"
    }
}

actor NativeTranscription: TranscriptionProvider {
    private var active: (id: UUID, task: Task<String, Error>)?

    func transcribe(audio: Data, locale: String, dictionary: [String]) async throws -> String {
        guard #available(macOS 26, *) else {
            throw DictationFailure.runtime("Apple native recognition needs macOS 26; use the baseline release on older Macs.")
        }
        active?.task.cancel()
        let id = UUID()
        let task = Task {
            let text = try await AppleFileRecognizer().transcribe(wav: audio, locale: locale, dictionary: dictionary)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DictationFailure.noAudio }
            return text
        }
        active = (id, task)
        defer { if active?.id == id { active = nil } }
        do { return try await task.value }
        catch RecognitionError.assetsNotInstalled {
            throw DictationFailure.runtime("Install Apple speech assets from the AavAI menu first. This requires an initial download.")
        } catch RecognitionError.unavailable {
            throw DictationFailure.runtime("Apple SpeechTranscriber is unavailable for this device or locale.")
        }
    }

    func cancel() async { active?.task.cancel(); active = nil }
}
