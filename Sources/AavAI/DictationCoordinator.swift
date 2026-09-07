import AppKit
import Foundation

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var history: [TranscriptEntry] = []

    private let audio: AudioCapturing
    private let transcription: TranscriptionProvider
    private let cleanup: CleanupProviding
    private let focus: FocusReading
    private let inserter: TextInserting
    private let historyStore: HistoryStoring
    private let dictionary: DictionaryStore
    private let isServiceReady: @MainActor () -> Bool
    private var snapshot: FocusSnapshot?
    private var processingStartedAt: ContinuousClock.Instant?

    init(audio: AudioCapturing, transcription: TranscriptionProvider, cleanup: CleanupProviding,
         focus: FocusReading, inserter: TextInserting, history: HistoryStoring, dictionary: DictionaryStore,
         isServiceReady: @escaping @MainActor () -> Bool = { true }) {
        self.audio = audio; self.transcription = transcription; self.cleanup = cleanup
        self.focus = focus; self.inserter = inserter; self.historyStore = history; self.dictionary = dictionary
        self.isServiceReady = isServiceReady
    }

    func loadHistory() async { history = await historyStore.list() }

    func start() async {
        guard state == .idle || isTerminal else { return }
        guard isServiceReady() else {
            state = .failed(.runtime("Still starting. Try again in a moment."), recoverableText: nil)
            return
        }
        let captured = focus.capture()
        guard captured.processIdentifier != 0 else {
            state = .failed(.permissionDenied("Accessibility"), recoverableText: nil)
            return
        }
        guard !captured.context.isSecure else { state = .failed(.secureField, recoverableText: nil); return }
        do {
            snapshot = captured
            try await audio.start(); state = .listening
        } catch { state = .failed(error as? DictationFailure ?? .permissionDenied("Microphone"), recoverableText: nil) }
    }

    func finish() async {
        guard state == .listening, let snapshot else { return }
        do {
            processingStartedAt = .now
            state = .finalizing
            let data = try await audio.stop()
            guard !data.isEmpty else { throw DictationFailure.noAudio }
            let raw = try await transcription.transcribe(audio: data, locale: "en", dictionary: dictionary.terms)
            state = .cleaning
            let result = try await cleanup.clean(.init(transcript: raw, context: snapshot.context, locale: "en", dictionary: dictionary.terms))
            state = .inserting
            let insertion = await inserter.insert(result.text, into: snapshot)
            guard insertion.succeeded else {
                let failure: DictationFailure = insertion.reason == "focusChanged" ? .focusChanged : .insertion(insertion.reason ?? "Unknown")
                throw RecoverableFailure(failure: failure, text: result.text)
            }
            let duration = processingStartedAt.map { instant in
                let components = instant.duration(to: .now).components
                return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
            } ?? 0
            let entry = TranscriptEntry(id: UUID(), createdAt: .now, rawText: raw, cleanedText: result.text,
                                        applicationName: snapshot.context.applicationName, latencyMilliseconds: duration)
            try await historyStore.append(entry); history = await historyStore.list(); state = .completed(result.text)
        } catch let recoverable as RecoverableFailure {
            state = .failed(recoverable.failure, recoverableText: recoverable.text)
        } catch let failure as DictationFailure {
            state = .failed(failure, recoverableText: nil)
        } catch {
            state = .failed(.transcription(error.localizedDescription), recoverableText: nil)
        }
    }

    func cancel() async { await audio.cancel(); state = .cancelled; resetAfterDelay() }
    func reset() { state = .idle; snapshot = nil; processingStartedAt = nil }
    func deleteHistory(id: UUID) async { try? await historyStore.delete(id: id); history = await historyStore.list() }
    func deleteAllHistory() async { try? await historyStore.deleteAll(); history = [] }

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
