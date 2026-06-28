import Foundation

/// A skill reduced to what retrieval needs: a `trigger` phrase to exact-match against the user's
/// turn, a compact `matchText` to rank by similarity, and a `source` so the caller knows which
/// prompt block it belongs in. Deliberately neutral so voice-taught and installed skills rank in one
/// pool against one budget.
struct SkillCandidate: Equatable, Identifiable {
    enum Source: Equatable { case voice, installed }
    let id: String
    let trigger: String      // exact phrase / name; never dropped if it appears in the turn
    let matchText: String    // trigger + summary, used only for similarity ranking
    let source: Source
}

/// Selects the skills worth injecting for the current turn, so a growing skill bank doesn't bloat
/// every system prompt. Both skill stores dump their whole library today; that's fine for a handful
/// but degrades as the library grows (most relevantly once Skill Self-Evolution starts adding
/// skills). Pure: the embedding similarity is **injected**, so the ranking logic is fully testable
/// without a model.
///
/// Two rules, applied in order:
///   1. **Never drop an exact trigger match.** A skill whose `trigger` substring-appears in the turn
///      is always kept — this preserves the existing exact-trigger behaviour, even past the budget.
///   2. **Fill the rest by relevance.** Remaining slots up to `topK` go to the highest-similarity
///      candidates.
///
/// Below `minCount` total candidates (or with an empty turn) retrieval is a **no-op** — it returns
/// everything, exactly reproducing today's dump-all behaviour. Output preserves the input order so
/// the formatted block is deterministic.
enum SkillRetriever {

    static func select(
        turn: String,
        candidates: [SkillCandidate],
        similarity: (SkillCandidate) -> Float,
        topK: Int,
        minCount: Int
    ) -> [SkillCandidate] {
        let trimmedTurn = turn.trimmingCharacters(in: .whitespacesAndNewlines)
        // Below the floor, or nothing to match against → preserve dump-all behaviour.
        guard candidates.count > minCount, !trimmedTurn.isEmpty else { return candidates }

        let loweredTurn = trimmedTurn.lowercased()

        // Rule 1: exact trigger matches are always kept, regardless of similarity or budget.
        var kept = Set<Int>()
        for (i, c) in candidates.enumerated() {
            let trigger = c.trigger.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !trigger.isEmpty, loweredTurn.contains(trigger) { kept.insert(i) }
        }

        // Rule 2: fill the remaining budget by injected similarity among the rest.
        if kept.count < topK {
            let ranked = candidates.enumerated()
                .filter { !kept.contains($0.offset) }
                .map { (offset: $0.offset, score: similarity($0.element)) }
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            for entry in ranked.prefix(topK - kept.count) { kept.insert(entry.offset) }
        }

        // Stable output: original order.
        return candidates.enumerated()
            .filter { kept.contains($0.offset) }
            .map { $0.element }
    }
}
