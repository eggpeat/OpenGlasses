import Foundation

/// Pure orchestration of one web-grounded re-ask (Plan BI): search → splice results into a
/// grounding prompt → regenerate **exactly once** (no loops, bounded latency). Any failure —
/// empty search, search throw, regenerate throw, empty regeneration — falls back to the
/// original answer, so the gate is never worse than doing nothing.
///
/// The transparency prefix means a re-grounded answer is never silently swapped in for the
/// model's own — consistent with the project's no-silent-fallback stance.
enum UncertaintyReask {

    static let transparencyPrefix = "Checked the web for that — "

    static func answer(
        question: String,
        originalAnswer: String,
        search: (String) async throws -> String?,
        regenerate: (String) async throws -> String
    ) async -> String {
        // Search failed, threw, or came back empty → the original answer stands.
        let searched = (try? await search(question)) ?? nil
        guard let results = searched?.trimmingCharacters(in: .whitespacesAndNewlines),
              !results.isEmpty else {
            return originalAnswer
        }

        let grounding = """
        Web search results for "\(question)":

        \(results)

        Using these results where they are relevant, answer the user's question concisely. \
        If the results don't actually answer it, say so briefly.
        Question: \(question)
        """

        // Exactly one regeneration; a throw or empty reply falls back to the original.
        guard let regenerated = (try? await regenerate(grounding))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !regenerated.isEmpty else {
            return originalAnswer
        }
        return transparencyPrefix + regenerated
    }
}
