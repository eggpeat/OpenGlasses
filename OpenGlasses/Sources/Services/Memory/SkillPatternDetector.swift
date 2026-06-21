import Foundation

/// A proposed `voice_skill` distilled from a repeated multi-step request.
struct SkillSuggestion: Equatable {
    let toolSignature: [String]   // the ordered tools the repeated request runs
    let count: Int                // how many times it's been seen
    let triggerHint: String       // a suggested trigger phrase (the user's latest wording)
}

/// Watches completed turns for a **repeated multi-tool sequence** and, once it crosses a
/// threshold, suggests saving it as a skill — the "autonomous skill creation" idea, but as a
/// suggestion the user confirms (never auto-saved). Holds a small rolling frequency map;
/// deterministic given the sequence of `record(...)` calls, so it's unit-testable.
final class SkillPatternDetector {
    private let threshold: Int
    private var counts: [String: Int] = [:]
    private var latestHint: [String: String] = [:]
    private var suggested: Set<String> = []

    init(threshold: Int = 3) {
        self.threshold = max(2, threshold)
    }

    /// Record a completed turn. Returns a suggestion the first time a multi-tool sequence
    /// reaches the threshold (once per distinct sequence).
    func record(toolNames: [String], triggerHint: String) -> SkillSuggestion? {
        guard toolNames.count >= 2 else { return nil }          // only multi-step requests
        let key = toolNames.joined(separator: ">")
        counts[key, default: 0] += 1
        latestHint[key] = triggerHint

        guard counts[key]! >= threshold, !suggested.contains(key) else { return nil }
        suggested.insert(key)
        return SkillSuggestion(toolSignature: toolNames, count: counts[key]!,
                               triggerHint: triggerHint)
    }

    func reset() {
        counts.removeAll()
        latestHint.removeAll()
        suggested.removeAll()
    }
}
