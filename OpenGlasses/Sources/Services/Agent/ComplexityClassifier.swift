import Foundation

/// Decides whether a request should run through the deliberate plan-then-execute loop
/// (Plan S, Phase 2). Layers an **optional** LLM verdict on top of the pure
/// `AgentComplexity` keyword heuristic: the heuristic is the free fast path, and the
/// LLM is consulted only for the ambiguous middle — a request with multiple action
/// cues but no clear sequencer word — so we never pay a classification round-trip on
/// ordinary chat. Pure + headless-testable; the LLM call itself is injected.
enum ComplexityClassifier {

    enum Decision: Equatable { case singleShot, multiStep }

    /// Combine the heuristic with an optional LLM verdict (`nil` = not consulted /
    /// unavailable). Multi-step if **either** signals it — the LLM only adds recall the
    /// keyword heuristic misses; it can't veto a heuristic positive.
    static func decide(heuristic: Bool, llmVerdict: Bool?) -> Decision {
        (heuristic || (llmVerdict ?? false)) ? .multiStep : .singleShot
    }

    /// Whether spending an LLM call to classify is worthwhile: only when the cheap
    /// heuristic is **negative** but the request still carries multi-action signals —
    /// two or more distinct action cues, or an action cue plus a sequencer the heuristic
    /// didn't fully credit. Avoids a round-trip on "what's the weather".
    static func shouldConsultLLM(_ request: String) -> Bool {
        guard !AgentComplexity.isMultiStep(request) else { return false }  // heuristic already decided
        let lower = request.lowercased()
        let cues = AgentComplexity.actionCueCount(lower)
        let hasSequencer = AgentComplexity.hasSequencer(lower)
        return cues >= 2 || (cues >= 1 && hasSequencer)
    }

    /// The yes/no classification prompt for the injected LLM. Tiny and history-free.
    static let systemPrompt = """
    Classify whether the user's request needs MULTIPLE sequential tool actions to fulfil \
    (e.g. "take a photo and email it to Sam") versus a SINGLE action or a plain question. \
    Reply with exactly one word: "multi" or "single". No punctuation, no explanation.
    """

    /// Parse the LLM reply into a verdict (`nil` if unrecognisable).
    static func parseVerdict(_ reply: String) -> Bool? {
        let r = reply.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("multi") { return true }
        if r.hasPrefix("single") { return false }
        return nil
    }
}
