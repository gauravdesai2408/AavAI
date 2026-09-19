import AppKit
import Foundation

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var history: [TranscriptEntry] = []
    @Published private(set) var rawTranscript = ""
    @Published private(set) var polishedTranscript = ""
    @Published private(set) var isStarting = false
    @Published private(set) var storageError: String?
    private var previewOnly = false
    private var isCancelling = false
    private var sessionID = UUID()

    private let audio: AudioCapturing
    private let transcription: TranscriptionProvider
    private let cleanup: CleanupProviding
    private let focus: FocusReading
    private let inserter: TextInserting
    private let historyStore: HistoryStoring
    private let dictionary: DictionaryStore
    private let isServiceReady: @MainActor () -> Bool
    private let shouldSaveHistory: @MainActor () -> Bool
    private let retentionDays: @MainActor () -> Int
    private var snapshot: FocusSnapshot?
    private var processingStartedAt: ContinuousClock.Instant?

    init(audio: AudioCapturing, transcription: TranscriptionProvider, cleanup: CleanupProviding,
         focus: FocusReading, inserter: TextInserting, history: HistoryStoring, dictionary: DictionaryStore,
         isServiceReady: @escaping @MainActor () -> Bool = { true },
         shouldSaveHistory: @escaping @MainActor () -> Bool = { true },
         retentionDays: @escaping @MainActor () -> Int = { 0 }) {
        self.audio = audio; self.transcription = transcription; self.cleanup = cleanup
        self.focus = focus; self.inserter = inserter; self.historyStore = history; self.dictionary = dictionary
        self.isServiceReady = isServiceReady
        self.shouldSaveHistory = shouldSaveHistory
        self.retentionDays = retentionDays
    }

    func loadHistory() async {
        do {
            try await historyStore.validate()
            try await enforceRetention()
            history = await historyStore.list(); storageError = nil
        }
        catch { storageError = "History could not be loaded safely. Existing data has not been changed." }
    }

    func start(previewOnly: Bool = false) async {
        guard !isStarting, !isCancelling else { return }
        guard state == .idle || isTerminal else { return }
        guard isServiceReady() else {
            state = .failed(.runtime("Still starting. Try again in a moment."), recoverableText: nil)
            return
        }
        let captured = previewOnly ? FocusSnapshot(
            context: .init(bundleIdentifier: Bundle.main.bundleIdentifier, applicationName: "AavAI", category: .generic, nearbyText: "", isSecure: false),
            element: nil, processIdentifier: ProcessInfo.processInfo.processIdentifier
        ) : focus.capture()
        guard captured.processIdentifier != 0 else {
            state = .failed(.permissionDenied("Accessibility"), recoverableText: nil)
            return
        }
        guard !captured.context.isSecure else { state = .failed(.secureField, recoverableText: nil); return }
        isStarting = true
        defer { isStarting = false }
        sessionID = UUID()
        let currentSession = sessionID
        do {
            self.previewOnly = previewOnly
            rawTranscript = ""
            polishedTranscript = ""
            snapshot = captured
            try await audio.start()
            guard sessionID == currentSession else {
                await audio.cancel()
                return
            }
            state = .listening
        } catch {
            guard sessionID == currentSession else { return }
            state = .failed(error as? DictationFailure ?? .permissionDenied("Microphone"), recoverableText: nil)
        }
    }

    func finish() async {
        guard state == .listening, let snapshot else { return }
        let currentSession = sessionID
        let showOnly = previewOnly
        do {
            processingStartedAt = .now
            state = .finalizing
            let data = try await audio.stop()
            guard sessionID == currentSession else { return }
            guard !data.isEmpty else { throw DictationFailure.noAudio }
            let raw = try await transcription.transcribe(audio: data, locale: "en", dictionary: dictionary.terms)
            guard sessionID == currentSession else { return }
            rawTranscript = raw
            state = .cleaning
            let result = try await cleanup.clean(.init(transcript: raw, context: snapshot.context, locale: "en", dictionary: dictionary.terms))
            guard sessionID == currentSession else { return }
            polishedTranscript = result.text
            let duration = processingStartedAt.map { instant in
                let components = instant.duration(to: .now).components
                return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
            } ?? 0
            let entry = TranscriptEntry(id: UUID(), createdAt: .now, rawText: raw, cleanedText: result.text,
                                        applicationName: snapshot.context.applicationName, latencyMilliseconds: duration)
            if shouldSaveHistory() { do {
                try await historyStore.append(entry)
                try await enforceRetention()
                history = await historyStore.list()
                storageError = nil
            } catch { storageError = "The transcript could not be saved. You can still copy or insert it." } }
            guard sessionID == currentSession else { return }
            if !showOnly {
                state = .inserting
                let insertion = await inserter.insert(result.text, into: snapshot)
                guard sessionID == currentSession else { return }
                guard insertion.succeeded else {
                    let failure: DictationFailure = insertion.reason == "focusChanged" ? .focusChanged : .insertion(insertion.reason ?? "Unknown")
                    throw RecoverableFailure(failure: failure, text: result.text)
                }
            }
            state = .completed(result.text)
        } catch let recoverable as RecoverableFailure {
            guard sessionID == currentSession else { return }
            state = .failed(recoverable.failure, recoverableText: recoverable.text)
        } catch let failure as DictationFailure {
            guard sessionID == currentSession else { return }
            state = .failed(failure, recoverableText: nil)
        } catch {
            guard sessionID == currentSession else { return }
            state = .failed(.transcription(error.localizedDescription), recoverableText: nil)
        }
    }

    func cancel() async {
        guard !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }
        sessionID = UUID()
        state = .cancelled
        await audio.cancel()
        await transcription.cancel()
    }
    func reset() { sessionID = UUID(); state = .idle; snapshot = nil; processingStartedAt = nil }
    func deleteHistory(id: UUID) async {
        do { try await historyStore.delete(id: id); history = await historyStore.list(); storageError = nil }
        catch { storageError = "Deletion failed. The saved transcript has not been confirmed deleted." }
    }
    func deleteAllHistory() async {
        do { try await historyStore.deleteAll(); history = await historyStore.list(); storageError = nil }
        catch { storageError = "Deletion failed. Saved history has not been confirmed deleted." }
    }

    private func enforceRetention() async throws {
        let days = retentionDays()
        guard [7, 30, 90].contains(days) else { return }
        try await historyStore.delete(before: Date.now.addingTimeInterval(-Double(days) * 86_400))
    }

    func exportData(dictionary: [String]) async throws -> Data {
        try await historyStore.validate()
        try await enforceRetention()
        let entries = await historyStore.list()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(LocalDataExport(version: 1, exportedAt: .now, history: entries, dictionary: dictionary))
    }

    var recoverableText: String? {
        if case .failed(_, let text) = state { return text }
        return nil
    }

    func copyRecoverableText() {
        guard let recoverableText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recoverableText, forType: .string)
    }

    func retryLastInsertion() async {
        guard let recoverableText, let snapshot else { return }
        state = .inserting
        let result = await inserter.insert(recoverableText, into: snapshot)
        state = result.succeeded ? .completed(recoverableText) : .failed(.focusChanged, recoverableText: recoverableText)
    }

    func insertHistoryEntry(_ entry: TranscriptEntry) async {
        let target = focus.capture()
        guard !target.context.isSecure else { state = .failed(.secureField, recoverableText: entry.cleanedText); return }
        state = .inserting
        let result = await inserter.insert(entry.cleanedText, into: target)
        state = result.succeeded ? .completed(entry.cleanedText) : .failed(.focusChanged, recoverableText: entry.cleanedText)
    }

    func copyHistoryEntry(_ entry: TranscriptEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.cleanedText, forType: .string)
    }

    private var isTerminal: Bool {
        switch state { case .completed, .cancelled, .failed: true; default: false }
    }
    private func resetAfterDelay() { Task { try? await Task.sleep(for: .seconds(1)); reset() } }
}

private struct RecoverableFailure: Error { let failure: DictationFailure; let text: String }

private struct LocalDataExport: Encodable {
    let version: Int
    let exportedAt: Date
    let history: [TranscriptEntry]
    let dictionary: [String]
}
