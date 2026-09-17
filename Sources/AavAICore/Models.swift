import Foundation

public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case email, workChat, document, generic
}

public struct FocusContext: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let category: AppCategory
    public let nearbyText: String
    public let isSecure: Bool
    public init(bundleIdentifier: String?, applicationName: String?, category: AppCategory, nearbyText: String, isSecure: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.category = category
        self.nearbyText = nearbyText
        self.isSecure = isSecure
    }
}

public struct CleanupRequest: Codable, Equatable, Sendable {
    public let transcript: String
    public let context: FocusContext
    public let locale: String
    public let dictionary: [String]
    public init(transcript: String, context: FocusContext, locale: String, dictionary: [String]) {
        self.transcript = transcript
        self.context = context
        self.locale = locale
        self.dictionary = dictionary
    }
}

public struct CleanupResult: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Double
    public let warnings: [String]
    public init(text: String, confidence: Double, warnings: [String]) {
        self.text = text
        self.confidence = confidence
        self.warnings = warnings
    }
}

public enum InsertionMethod: String, Codable, Sendable { case accessibility, clipboardPaste, clipboardOnly }

public struct InsertionResult: Codable, Equatable, Sendable {
    public let method: InsertionMethod
    public let succeeded: Bool
    public let reason: String?
    public let targetApplication: String?
    public var retryEligible: Bool { !succeeded }
    public init(method: InsertionMethod, succeeded: Bool, reason: String?, targetApplication: String?) {
        self.method = method
        self.succeeded = succeeded
        self.reason = reason
        self.targetApplication = targetApplication
    }
}

public struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let rawText: String
    public let cleanedText: String
    public let applicationName: String?
    public let latencyMilliseconds: Int
    public init(id: UUID, createdAt: Date, rawText: String, cleanedText: String, applicationName: String?, latencyMilliseconds: Int) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.applicationName = applicationName
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public enum DictationFailure: Error, Equatable, Sendable {
    case permissionDenied(String)
    case noAudio
    case audioDeviceChanged
    case transcription(String)
    case cleanup(String)
    case runtime(String)
    case focusChanged
    case secureField
    case insertion(String)

    public var message: String {
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

public enum DictationState: Equatable, Sendable {
    case idle
    case listening
    case finalizing
    case cleaning
    case inserting
    case completed(String)
    case cancelled
    case failed(DictationFailure, recoverableText: String?)
}
