import Foundation

public struct PCMFrame: Sendable, Equatable {
    public let sessionID: UUID
    public let sequence: Int
    public let sampleRate: Double
    /// Mono float PCM. One frame is at most one second; zero is not a VAD decision.
    public let samples: [Float]

    public init(sessionID: UUID, sequence: Int, sampleRate: Double, samples: [Float]) throws {
        guard sampleRate.isFinite, (8_000...96_000).contains(sampleRate), sequence >= 0,
              !samples.isEmpty, samples.count <= Int(sampleRate),
              samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else {
            throw RecognitionError.invalidAudio
        }
        self.sessionID = sessionID; self.sequence = sequence
        self.sampleRate = sampleRate; self.samples = samples
    }
}

public enum RecognitionError: Error, Equatable {
    case invalidAudio, unavailable, assetsNotInstalled, staleSession, outOfOrderFrame
}

public struct RecognitionCapabilities: Sendable {
    public let engineID: String
    public let localOnly: Bool
    public let supportsPartials: Bool
    public let assetsManagedBySystem: Bool
    public init(engineID: String, localOnly: Bool, supportsPartials: Bool, assetsManagedBySystem: Bool) {
        self.engineID = engineID; self.localOnly = localOnly
        self.supportsPartials = supportsPartials; self.assetsManagedBySystem = assetsManagedBySystem
    }
}

public struct RecognitionEvent: Sendable {
    public let sessionID: UUID
    public let text: String
    public let isFinal: Bool
    public let audioStartSeconds: Double
    public let audioDurationSeconds: Double
    public init(sessionID: UUID, text: String, isFinal: Bool, audioStartSeconds: Double, audioDurationSeconds: Double) {
        self.sessionID = sessionID; self.text = text; self.isFinal = isFinal
        self.audioStartSeconds = audioStartSeconds; self.audioDurationSeconds = audioDurationSeconds
    }
}

public protocol StreamingRecognition: Sendable {
    var capabilities: RecognitionCapabilities { get }
    func recognize(sessionID: UUID, frames: AsyncThrowingStream<PCMFrame, Error>,
                   locale: String, dictionary: [String]) -> AsyncThrowingStream<RecognitionEvent, Error>
}

/// A bounded ring for capture startup/chunk overlap. Never opens a microphone.
public struct AudioWindow: Sendable {
    public let capacity: Int
    public private(set) var samples: [Float] = []
    public init(capacity: Int) { self.capacity = max(0, capacity) }
    public mutating func append(_ incoming: [Float]) {
        guard capacity > 0 else { return }
        if incoming.count >= capacity { samples = Array(incoming.suffix(capacity)); return }
        let overflow = max(0, samples.count + incoming.count - capacity)
        samples.removeFirst(overflow)
        samples.append(contentsOf: incoming)
    }
    public mutating func clear() { samples.removeAll(keepingCapacity: false) }
}

/// UI adapters accept only events belonging to the current capture. Partial text
/// is never exposed as insertable text, including after cancellation.
public struct RecognitionSession: Sendable {
    public private(set) var id: UUID?
    public private(set) var provisionalText = ""
    public private(set) var finalText = ""
    public private(set) var completed = false
    public init() {}
    @discardableResult public mutating func begin() -> UUID {
        let newID = UUID(); id = newID; provisionalText = ""; finalText = ""; completed = false
        return newID
    }
    public mutating func accept(_ event: RecognitionEvent) {
        guard id == event.sessionID, !completed else { return }
        if event.isFinal {
            finalText += (finalText.isEmpty ? "" : " ") + event.text
            provisionalText = ""
        } else { provisionalText = event.text }
    }
    public mutating func finish(sessionID: UUID) {
        guard id == sessionID else { return }
        completed = true; provisionalText = ""
    }
    public mutating func cancel() { id = nil; provisionalText = ""; finalText = ""; completed = false }
    public var insertableText: String? { completed && !finalText.isEmpty ? finalText : nil }
}
