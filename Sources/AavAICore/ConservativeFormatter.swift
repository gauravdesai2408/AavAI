import Foundation

/// Does not infer missing words, remove fillers, or rewrite corrections: those
/// transformations require evaluation evidence before they can become defaults.
public struct ConservativeFormatter: Sendable {
    public init() {}

    public func format(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
