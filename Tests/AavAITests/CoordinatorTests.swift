import Foundation
import Testing
@testable import AavAI

@MainActor
@Suite("Dictation coordinator")
struct CoordinatorTests {
    @Test func successfulSessionPersistsAndInserts() async {
        let history = MemoryHistory()
        let dictionary = DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let inserter = FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: "Notes"))
        let coordinator = DictationCoordinator(audio: FakeAudio(), transcription: FakeTranscription(), cleanup: FakeCleanup(),
                                               focus: FakeFocus(), inserter: inserter, history: history, dictionary: dictionary)
        await coordinator.start()
        #expect(coordinator.state == .listening)
        await coordinator.finish()
        #expect(coordinator.state == .completed("Hello world."))
        let historyCount = await history.list().count
        #expect(historyCount == 1)
        #expect(inserter.values == ["Hello world."])
    }

    @Test func focusFailureKeepsRecoverableText() async {
        let dictionary = DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = DictationCoordinator(audio: FakeAudio(), transcription: FakeTranscription(), cleanup: FakeCleanup(), focus: FakeFocus(),
            inserter: FakeInserter(result: .init(method: .clipboardOnly, succeeded: false, reason: "focusChanged", targetApplication: "Notes")),
            history: MemoryHistory(), dictionary: dictionary)
        await coordinator.start(); await coordinator.finish()
        #expect(coordinator.state == .failed(.focusChanged, recoverableText: "Hello world."))
    }

    @Test func unavailableRuntimeDoesNotStartMicrophone() async {
        let audio = FakeAudio()
        let dictionary = DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = DictationCoordinator(
            audio: audio, transcription: FakeTranscription(), cleanup: FakeCleanup(), focus: FakeFocus(),
            inserter: FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: "Notes")),
            history: MemoryHistory(), dictionary: dictionary, isServiceReady: { false }
        )
        await coordinator.start()
        #expect(audio.startCount == 0)
        #expect(coordinator.state == .failed(.runtime("Still starting. Try again in a moment."), recoverableText: nil))
    }

    @Test func cancellationNeverTranscribesOrInserts() async {
        let audio = FakeAudio()
        let inserter = FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: "Notes"))
        let dictionary = DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = DictationCoordinator(
            audio: audio, transcription: FakeTranscription(), cleanup: FakeCleanup(), focus: FakeFocus(),
            inserter: inserter, history: MemoryHistory(), dictionary: dictionary
        )
        await coordinator.start()
        await coordinator.cancel()
        #expect(audio.cancelCount == 1)
        #expect(inserter.values.isEmpty)
    }

    @Test func secureFieldNeverStartsRecordingOrInserts() async {
        let audio = FakeAudio()
        let inserter = FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: "Login"))
        let dictionary = DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = DictationCoordinator(
            audio: audio, transcription: FakeTranscription(), cleanup: FakeCleanup(), focus: FakeSecureFocus(),
            inserter: inserter, history: MemoryHistory(), dictionary: dictionary
        )

        await coordinator.start()

        #expect(coordinator.state == .failed(.secureField, recoverableText: nil))
        #expect(audio.startCount == 0)
        #expect(inserter.values.isEmpty)
    }

    @Test func failedInsertionCanBeRetried() async {
        let inserter = SequenceInserter(results: [
            .init(method: .clipboardOnly, succeeded: false, reason: "focusChanged", targetApplication: "Notes"),
            .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: "Notes")
        ])
        let dictionary = DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = DictationCoordinator(
            audio: FakeAudio(), transcription: FakeTranscription(), cleanup: FakeCleanup(), focus: FakeFocus(),
            inserter: inserter, history: MemoryHistory(), dictionary: dictionary
        )
        await coordinator.start(); await coordinator.finish(); await coordinator.retryLastInsertion()
        #expect(coordinator.state == .completed("Hello world."))
        #expect(inserter.values == ["Hello world.", "Hello world."])
    }

    @Test func historyIsEncryptedAndCanBeReloaded() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "aavai-history-\(UUID().uuidString)")
        let key = Data(repeating: 7, count: 32)
        let entry = TranscriptEntry(id: UUID(), createdAt: .now, rawText: "secret raw", cleanedText: "Secret cleaned.", applicationName: "Notes", latencyMilliseconds: 10)
        let store = JSONHistoryStore(fileURL: file, keyData: key)
        try await store.append(entry)
        let bytes = try Data(contentsOf: file)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Secret cleaned"))
        let reopened = JSONHistoryStore(fileURL: file, keyData: key)
        #expect(await reopened.list() == [entry])
        try? FileManager.default.removeItem(at: file)
    }
}

final class FakeAudio: AudioCapturing, @unchecked Sendable {
    var startCount = 0
    var cancelCount = 0
    func start() async throws { startCount += 1 }
    func stop() async throws -> Data { Data([1]) }
    func cancel() async { cancelCount += 1 }
}
struct FakeTranscription: TranscriptionProvider { func transcribe(audio: Data, locale: String, dictionary: [String]) async throws -> String { "um hello world" } }
struct FakeCleanup: CleanupProviding { func clean(_ request: CleanupRequest) async throws -> CleanupResult { .init(text: "Hello world.", confidence: 1, warnings: []) } }
@MainActor struct FakeFocus: FocusReading { func capture() -> FocusSnapshot { .init(context: .init(bundleIdentifier: "com.apple.Notes", applicationName: "Notes", category: .document, nearbyText: "", isSecure: false), element: nil, processIdentifier: 1) } }
@MainActor struct FakeSecureFocus: FocusReading { func capture() -> FocusSnapshot { .init(context: .init(bundleIdentifier: "com.example.Login", applicationName: "Login", category: .generic, nearbyText: "", isSecure: true), element: nil, processIdentifier: 1) } }
@MainActor final class FakeInserter: TextInserting {
    let result: InsertionResult; var values: [String] = []
    init(result: InsertionResult) { self.result = result }
    func insert(_ text: String, into snapshot: FocusSnapshot) async -> InsertionResult { values.append(text); return result }
}
@MainActor final class SequenceInserter: TextInserting {
    private var results: [InsertionResult]
    var values: [String] = []
    init(results: [InsertionResult]) { self.results = results }
    func insert(_ text: String, into snapshot: FocusSnapshot) async -> InsertionResult {
        values.append(text)
        return results.isEmpty
            ? .init(method: .clipboardOnly, succeeded: false, reason: "noResult", targetApplication: nil)
            : results.removeFirst()
    }
}
actor MemoryHistory: HistoryStoring {
    var values: [TranscriptEntry] = []
    func list() -> [TranscriptEntry] { values }
    func append(_ entry: TranscriptEntry) { values.append(entry) }
    func delete(id: UUID) { values.removeAll { $0.id == id } }
    func deleteAll() { values = [] }
}
