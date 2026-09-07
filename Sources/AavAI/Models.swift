import Foundation

enum AppCategory: String, Codable, CaseIterable, Sendable {
    case email, workChat, document, generic
}

struct FocusContext: Codable, Equatable, Sendable {
    let bundleIdentifier: String?
    let applicationName: String?
    let category: AppCategory
    let nearbyText: String
    let isSecure: Bool
}

struct CleanupRequest: Codable, Equatable, Sendable {
    let transcript: String
    let context: FocusContext
    let locale: String
    let dictionary: [String]
}

struct CleanupResult: Codable, Equatable, Sendable {
    let text: String
    let confidence: Double
    let warnings: [String]
}

enum InsertionMethod: String, Codable, Sendable { case accessibility, clipboardPaste, clipboardOnly }

struct InsertionResult: Codable, Equatable, Sendable {
    let method: InsertionMethod
    let succeeded: Bool
    let reason: String?
    let targetApplication: String?
    var retryEligible: Bool { !succeeded }
}

struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let rawText: String
    let cleanedText: String
    let applicationName: String?
    let latencyMilliseconds: Int
}

enum DictationFailure: Error, Equatable, Sendable {
    case permissionDenied(String)
    case noAudio
    case audioDeviceChanged
    case transcription(String)
    case cleanup(String)
    case runtime(String)
    case focusChanged
    case secureField
    case insertion(String)

    var message: String {
        switch self {
        case .permissionDenied(let value): "Permission required: \(value)"
        case .noAudio: "No speech was detected."
        case .audioDeviceChanged: "The microphone changed during dictation. Please try again."
        case .transcription(let value): "Transcription failed: \(value)"
        case .cleanup(let value): "Cleanup failed: \(value)"
        case .runtime(let value): "Local AI unavailable: \(value)"
        case .focusChanged: "Focus changed. Your text is ready to copy."
        case .secureField: "AavAI never inserts text into secure fields."
        case .insertion(let value): "Insertion failed: \(value)"
        }
    }
}

enum DictationState: Equatable, Sendable {
    case idle
    case listening
    case finalizing
    case cleaning
    case inserting
    case completed(String)
    case cancelled
    case failed(DictationFailure, recoverableText: String?)
}
