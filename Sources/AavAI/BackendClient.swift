import Foundation

struct BackendClient: TranscriptionProvider, CleanupProviding {
    let baseURL: URL
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)

    func transcribe(audio: Data, locale: String, dictionary: [String]) async throws -> String {
        try validateEndpoint()
        var request = URLRequest(url: baseURL.appending(path: "v1/transcribe"))
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue(locale, forHTTPHeaderField: "X-Locale")
        request.setValue(dictionary.joined(separator: ","), forHTTPHeaderField: "X-Dictionary")
        request.timeoutInterval = 35
        request.httpBody = audio
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 422 { throw DictationFailure.noAudio }
            throw DictationFailure.transcription(Self.errorMessage(from: data) ?? "Backend unavailable")
        }
        return try JSONDecoder().decode(TranscriptResponse.self, from: data).text
    }

    func clean(_ requestValue: CleanupRequest) async throws -> CleanupResult {
        try validateEndpoint()
        var request = URLRequest(url: baseURL.appending(path: "v1/cleanup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(requestValue)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DictationFailure.cleanup(Self.errorMessage(from: data) ?? "Backend unavailable")
        }
        return try JSONDecoder().decode(CleanupResult.self, from: data)
    }

    private struct TranscriptResponse: Decodable { let text: String }
    private struct ErrorResponse: Decodable { let error: String }
    private static func errorMessage(from data: Data) -> String? { try? JSONDecoder().decode(ErrorResponse.self, from: data).error }

    static func isLocalEndpoint(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    private func validateEndpoint() throws {
        guard Self.isLocalEndpoint(baseURL) else {
            throw DictationFailure.runtime("Only a loopback backend is allowed. Remote content uploads are disabled.")
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
