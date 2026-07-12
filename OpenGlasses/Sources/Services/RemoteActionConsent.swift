import Foundation

/// Who is asking for a remote/agentic action (Plan BN P1) — every consent prompt carries its
/// origin, the same narration principle as BK P2c. Shared by Plan N (coding-agent confirms),
/// Plan BH (gateway remote invoke), and Plan BL (an MCP ops peer driving the glasses).
enum RemoteActionSource: Equatable {
    case assistant              // the local assistant's own high-impact tool call
    case codingAgent            // Plan N remote agent run
    case gateway                // Plan BH gateway remote invoke
    case opsPeer(label: String) // Plan BL MCP peer

    /// The subject of the consent sentence: "The coding agent wants: …".
    var line: String {
        switch self {
        case .assistant:          return "The assistant"
        case .codingAgent:        return "The coding agent"
        case .gateway:            return "The gateway"
        case .opsPeer(let label): return label.isEmpty ? "An ops platform" : label
        }
    }
}

/// One consent ask: the source plus what it wants. Pure prompt composition so the HUD card and
/// the spoken prompt always carry the attribution.
struct RemoteActionConsentRequest: Equatable {
    let source: RemoteActionSource
    let summary: String

    /// Source-attributed line for the card + audit: "The gateway wants: take a photo".
    var attributedSummary: String { "\(source.line) wants: \(summary)" }

    /// The spoken form.
    var spokenPrompt: String { "\(attributedSummary). Approve?" }
}

/// PURE voice yes/no interpretation for a pending consent prompt (the voice half of the shared
/// surface). Deliberately conservative: only short, unambiguous utterances count — anything else
/// returns `nil` and flows to the normal turn pipeline. Never guess an approval.
enum RemoteActionVoiceConsent {

    /// `true` = approve, `false` = deny, `nil` = not a consent answer.
    static func interpret(_ text: String) -> Bool? {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
        guard !normalized.isEmpty, normalized.split(separator: " ").count <= 3 else { return nil }
        if matches(normalized, any: approvals) { return true }
        if matches(normalized, any: denials) { return false }
        return nil
    }

    private static let approvals: Set<String> = [
        "yes", "yep", "yeah", "approve", "approved", "confirm", "confirmed",
        "go ahead", "do it", "proceed", "ok", "okay",
    ]
    private static let denials: Set<String> = [
        "no", "nope", "deny", "denied", "cancel", "stop", "decline", "abort", "don't",
    ]
    /// Trailing words that don't change the answer ("yes please", "cancel it").
    private static let politeness: Set<String> = ["please", "thanks", "sure", "it", "that"]

    private static func matches(_ text: String, any phrases: Set<String>) -> Bool {
        if phrases.contains(text) { return true }
        for phrase in phrases where text.hasPrefix(phrase + " ") {
            let rest = text.dropFirst(phrase.count + 1).split(separator: " ").map(String.init)
            if !rest.isEmpty, rest.allSatisfy({ politeness.contains($0) }) { return true }
        }
        return false
    }
}
