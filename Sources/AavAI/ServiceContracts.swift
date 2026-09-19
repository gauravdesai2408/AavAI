import Foundation

protocol AudioCapturing: AnyObject, Sendable {
    func start() async throws
    func stop() async throws -> Data
    func cancel() async
}

protocol TranscriptionProvider: Sendable {
    func transcribe(audio: Data, locale: String, dictionary: [String]) async throws -> String
    func cancel() async
}

extension TranscriptionProvider { func cancel() async {} }

protocol CleanupProviding: Sendable {
    func clean(_ request: CleanupRequest) async throws -> CleanupResult
}

@MainActor
protocol FocusReading: Sendable {
    func capture() -> FocusSnapshot
}

@MainActor
protocol TextInserting: Sendable {
    func insert(_ text: String, into snapshot: FocusSnapshot) async -> InsertionResult
}

protocol HistoryStoring: Sendable {
    func validate() async throws
    func list() async -> [TranscriptEntry]
    func append(_ entry: TranscriptEntry) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func delete(before cutoff: Date) async throws
}

extension HistoryStoring {
    func validate() async throws {}
    func delete(before cutoff: Date) async throws {
        for entry in await list() where entry.createdAt < cutoff { try await delete(id: entry.id) }
    }
}
