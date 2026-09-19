import Foundation
import Testing
@testable import AavAI

@Suite("Privacy storage")
struct PrivacyStorageTests {
    @Test func concurrentInitialWritesDoNotLoseEntries() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONHistoryStore(fileURL: dir.appending(path: "history"), keyData: Data(repeating: 9, count: 32))
        let expected = (0..<40).map { _ in entry() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for value in expected { group.addTask { try await store.append(value) } }
            try await group.waitForAll()
        }
        #expect(Set(await store.list().map(\.id)) == Set(expected.map(\.id)))
    }
    @Test func remoteEndpointsAreRejectedBeforeSendingContent() async {
        #expect(BackendClient.isLocalEndpoint(URL(string: "http://127.0.0.1:8787")!))
        for value in ["https://example.com", "http://127.0.0.1.example.com", "http://user:secret@localhost", "http://localhost?token=secret"] {
            let url = URL(string: value)!
            #expect(!BackendClient.isLocalEndpoint(url))
            await #expect(throws: (any Error).self) {
                try await BackendClient(baseURL: url).transcribe(audio: Data([1]), locale: "en", dictionary: [])
            }
        }
    }

    @MainActor @Test func exportContainsReadableLocalDataOnly() async throws {
        let history = MemoryHistory()
        let existing = entry(); await history.append(existing)
        let coordinator = DictationCoordinator(audio: FakeAudio(), transcription: FakeTranscription(), cleanup: FakeCleanup(),
            focus: FakeFocus(), inserter: FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: nil)),
            history: history, dictionary: DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let data = try await coordinator.exportData(dictionary: ["AavAI"])
        let archive = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(archive["version"] as? Int == 1)
        #expect(archive["dictionary"] as? [String] == ["AavAI"])
        #expect((archive["history"] as? [[String: Any]])?.first?["rawText"] as? String == existing.rawText)
        #expect(archive["audio"] == nil)
    }
    private func entry(date: Date = .now) -> TranscriptEntry {
        .init(id: UUID(), createdAt: date, rawText: "private raw", cleanedText: "private final", applicationName: "Notes", latencyMilliseconds: 1)
    }

    @Test func wrongKeyNeverOverwritesHistory() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "history")
        let original = JSONHistoryStore(fileURL: file, keyData: Data(repeating: 1, count: 32))
        let saved = entry()
        try await original.append(saved)
        let bytes = try Data(contentsOf: file)
        let wrongKey = JSONHistoryStore(fileURL: file, keyData: Data(repeating: 2, count: 32))
        await #expect(throws: (any Error).self) { try await wrongKey.validate() }
        await #expect(throws: (any Error).self) { try await wrongKey.deleteAll() }
        await #expect(throws: (any Error).self) { try await wrongKey.append(entry()) }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(await JSONHistoryStore(fileURL: file, keyData: Data(repeating: 1, count: 32)).list() == [saved])
    }

    @Test func corruptLegacyDataIsPreserved() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let corrupt = Data("not a transcript archive".utf8)
        try corrupt.write(to: file)
        let store = JSONHistoryStore(fileURL: file, keyData: Data(repeating: 3, count: 32))
        await #expect(throws: (any Error).self) { try await store.validate() }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test func failedWriteDoesNotChangeInMemoryHistory() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "history")
        let store = JSONHistoryStore(fileURL: file, keyData: Data(repeating: 4, count: 32))
        let saved = entry(); try await store.append(saved)
        // Replace this test-owned file with a directory to force atomic write failure.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await store.deleteAll() }
        #expect(await store.list() == [saved])
    }

    @Test func retentionAndDeletionPersistAfterReopen() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "history")
        let key = Data(repeating: 5, count: 32)
        let store = JSONHistoryStore(fileURL: file, keyData: key)
        let now = Date.now
        let recent = entry(date: now)
        try await store.append(entry(date: now.addingTimeInterval(-1000)))
        try await store.append(recent)
        try await store.delete(before: now.addingTimeInterval(-500))
        #expect(await JSONHistoryStore(fileURL: file, keyData: key).list() == [recent])
        try await store.deleteAll()
        #expect(await JSONHistoryStore(fileURL: file, keyData: key).list().isEmpty)
    }

    @MainActor @Test func dictionaryMigrationEncryptsAndReloads() async throws {
        let name = "aavai-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["Private Project", "AavAI"], forKey: "dictionaryTerms")
        let store = DictionaryStore(defaults: defaults, keyLoader: { Data(repeating: 6, count: 32) })
        await store.load()
        #expect(store.isReady)
        #expect(Set(store.terms) == Set(["Private Project", "AavAI"]))
        #expect(defaults.object(forKey: "dictionaryTerms") == nil)
        #expect(!String(decoding: defaults.data(forKey: "encryptedDictionaryV1")!, as: UTF8.self).contains("Private Project"))
        let reopened = DictionaryStore(defaults: defaults, keyLoader: { Data(repeating: 6, count: 32) })
        await reopened.load()
        #expect(reopened.terms == store.terms)
        reopened.deleteAll()
        let empty = DictionaryStore(defaults: defaults, keyLoader: { Data(repeating: 6, count: 32) })
        await empty.load(); #expect(empty.terms.isEmpty)
    }

    @MainActor @Test func dictionaryWrongKeyPreservesEncryptedAndLegacyData() async {
        let name = "aavai-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DictionaryStore(defaults: defaults, keyLoader: { Data(repeating: 7, count: 32) })
        await store.load(); store.add("private")
        let original = defaults.data(forKey: "encryptedDictionaryV1")
        defaults.set(["older release addition"], forKey: "dictionaryTerms")
        let wrong = DictionaryStore(defaults: defaults, keyLoader: { Data(repeating: 8, count: 32) })
        await wrong.load(); wrong.deleteAll()
        #expect(!wrong.isReady)
        #expect(wrong.errorMessage != nil)
        #expect(defaults.data(forKey: "encryptedDictionaryV1") == original)
        #expect(defaults.stringArray(forKey: "dictionaryTerms") == ["older release addition"])
    }

    @MainActor @Test func noHistoryModeStillProducesText() async {
        let history = MemoryHistory()
        let coordinator = DictationCoordinator(audio: FakeAudio(), transcription: FakeTranscription(), cleanup: FakeCleanup(),
            focus: FakeFocus(), inserter: FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: nil)),
            history: history, dictionary: DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), shouldSaveHistory: { false })
        await coordinator.start(previewOnly: true); await coordinator.finish()
        #expect(coordinator.state == .completed("Hello world."))
        #expect(await history.list().isEmpty)
    }

    @MainActor @Test func deletionFailureRemainsVisible() async {
        let existing = entry()
        let coordinator = DictationCoordinator(audio: FakeAudio(), transcription: FakeTranscription(), cleanup: FakeCleanup(),
            focus: FakeFocus(), inserter: FakeInserter(result: .init(method: .accessibility, succeeded: true, reason: nil, targetApplication: nil)),
            history: FailingDeletionHistory(entry: existing), dictionary: DictionaryStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        await coordinator.loadHistory(); await coordinator.deleteAllHistory()
        #expect(coordinator.history == [existing])
        #expect(coordinator.storageError != nil)
    }
}

private struct FailingDeletionHistory: HistoryStoring {
    let entry: TranscriptEntry
    func list() async -> [TranscriptEntry] { [entry] }
    func append(_ entry: TranscriptEntry) async throws {}
    func delete(id: UUID) async throws { throw HistoryStoreError.unreadable }
    func deleteAll() async throws { throw HistoryStoreError.unreadable }
}
