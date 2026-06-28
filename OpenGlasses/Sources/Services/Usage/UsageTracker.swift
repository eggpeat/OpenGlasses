import Foundation

/// Shared entry point for the LLM Cost & Usage Tracker (Plan AU): prices token
/// counts via `ModelPricing`, persists a `UsageRecord` to the local `UsageStore`,
/// and answers windowed rollups for `InsightsView`. Local-only — usage never
/// leaves the device.
///
/// `LLMService` parses each provider's usage block (pure, off the main actor) and
/// hands the token counts here; pricing + persistence happen on the main actor.
@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    let store: UsageStore

    /// Groups records from one usage "session" (app run / conversation). Rollups are
    /// by model + window, so this is just a grouping tag; reset on conversation clear.
    private(set) var sessionId = UUID().uuidString

    init(store: UsageStore? = nil) {
        self.store = store ?? UsageStore()
    }

    /// Start a new usage session (e.g. when the conversation is cleared).
    func startNewSession() { sessionId = UUID().uuidString }

    /// Price and persist one API call's usage. No-op when both token counts are 0.
    func record(provider: LLMProvider, model: String, tokensIn: Int, tokensOut: Int, at: Date = Date()) {
        guard tokensIn + tokensOut > 0 else { return }
        let cost = ModelPricing.estimate(model: model, tokensIn: tokensIn, tokensOut: tokensOut)
        store.insert(UsageRecord(sessionId: sessionId,
                                 provider: provider.rawValue,
                                 model: model,
                                 tokensIn: tokensIn,
                                 tokensOut: tokensOut,
                                 costUSD: cost,
                                 at: at))
    }

    /// Rolled-up tokens + estimated cost over the last `days`.
    func rollup(days: Int, now: Date = Date()) -> UsageRollup.Result {
        store.rollup(days: days, now: now)
    }

    /// Extract `(tokensIn, tokensOut)` from a provider's response JSON, or `nil` when
    /// no usage block is present. Pure and `nonisolated` so `LLMService` can call it
    /// on its own async context (the non-Sendable JSON never crosses an actor hop —
    /// only the resulting ints do).
    nonisolated static func parseTokens(provider: LLMProvider, json: [String: Any]) -> (tokensIn: Int, tokensOut: Int)? {
        switch provider {
        case .anthropic:
            guard let u = json["usage"] as? [String: Any] else { return nil }
            return (intValue(u["input_tokens"]), intValue(u["output_tokens"]))
        case .gemini:
            guard let u = json["usageMetadata"] as? [String: Any] else { return nil }
            return (intValue(u["promptTokenCount"]), intValue(u["candidatesTokenCount"]))
        case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom, .local, .appleOnDevice:
            guard let u = json["usage"] as? [String: Any] else { return nil }
            return (intValue(u["prompt_tokens"]), intValue(u["completion_tokens"]))
        }
    }

    private nonisolated static func intValue(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        return 0
    }
}
