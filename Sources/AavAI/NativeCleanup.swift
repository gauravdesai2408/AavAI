import AavAICore

struct NativeCleanup: CleanupProviding {
    func clean(_ request: CleanupRequest) async throws -> CleanupResult {
        .init(text: ConservativeFormatter().format(request.transcript), confidence: 0,
              warnings: ["Conservative formatting only; meaning preservation is not a confidence score."])
    }
}
