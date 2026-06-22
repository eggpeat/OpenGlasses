import Foundation
import Combine

/// A recall result: a synthesized answer plus the conversation turns it was drawn from.
struct RecallAnswer: Equatable {
    let summary: String
    let citations: [RecallHit]
    var isEmpty: Bool { citations.isEmpty }
}

/// Cross-session recall (Phase 2): searches the `ConversationIndex` and summarizes the top
/// turns into a cited answer. The summarizer is an injectable seam (wired in `AppState` to the
/// user's active provider via `LLMService.completeStateless` — which honors on-device models),
/// so the search→answer flow is unit-testable without a model. Shared singleton like
/// `BrainStore` / `StudyService`.
@MainActor
final class RecallService: ObservableObject {
    static let shared = RecallService()

    private var index: ConversationIndex?
    /// (question, hits) → answer text. Injected by `configure`; nil → a plain bulleted fallback.
    var summarize: ((String, [RecallHit]) async -> String)?

    var isConfigured: Bool { index != nil }

    init() {}

    func configure(index: ConversationIndex,
                   summarize: @escaping (String, [RecallHit]) async -> String) {
        self.index = index
        self.summarize = summarize
    }

    /// Raw search (no summarization).
    func search(_ phrase: String, now: Date = Date(), limit: Int = 12) -> [RecallHit] {
        index?.search(phrase: phrase, now: now, limit: limit) ?? []
    }

    /// Search + summarize into a cited answer.
    func recall(_ question: String, now: Date = Date()) async -> RecallAnswer {
        let hits = search(question, now: now, limit: 8)
        guard !hits.isEmpty else {
            return RecallAnswer(
                summary: "I couldn't find anything about that in our past conversations.",
                citations: []
            )
        }
        let summary = await summarize?(question, hits) ?? Self.fallbackSummary(hits)
        return RecallAnswer(summary: summary, citations: hits)
    }

    /// Bulleted snippets — used when no summarizer is wired (or it fails).
    static func fallbackSummary(_ hits: [RecallHit]) -> String {
        hits.prefix(5).map { "• \($0.snippet)" }.joined(separator: "\n")
    }

    /// The prompt the configured summarizer runs: answer strictly from the cited excerpts.
    static func summarizationPrompt(question: String, hits: [RecallHit]) -> (system: String, user: String) {
        let excerpts = hits.enumerated().map { i, hit in
            "[\(i + 1)] (\(hit.role), \(RecallTimestamp.string(from: hit.timestamp))) \(hit.text)"
        }.joined(separator: "\n")
        let system = """
        You answer the user's question using ONLY the excerpts from their past conversations \
        below. Be concise and conversational. Cite excerpts inline like [1]. If the excerpts \
        don't actually answer the question, say you couldn't find it.
        """
        let user = "Question: \(question)\n\nPast conversation excerpts:\n\(excerpts)"
        return (system, user)
    }
}
