import Foundation

/// Per-model API pricing (USD per 1M tokens) for the LLM Cost & Usage Tracker (Plan AU).
///
/// Pure: a bundled default table (which inevitably drifts) plus runtime `overrides`,
/// matched by longest model-id prefix so dated variants (`claude-opus-4-8`,
/// `gpt-4o-2024-…`) resolve to their family. An unknown/unpriced model yields `nil`
/// — the tracker reports tokens and omits the dollar figure rather than guessing.
enum ModelPricing {

    struct Rate: Equatable {
        let inputPer1M: Double
        let outputPer1M: Double
        init(_ inputPer1M: Double, _ outputPer1M: Double) {
            self.inputPer1M = inputPer1M
            self.outputPer1M = outputPer1M
        }
    }

    /// Bundled defaults. Keys are matched as lowercased prefixes of the model id,
    /// longest match wins (so `gpt-4o-mini` beats `gpt-4o`). Representative public
    /// list prices at time of writing; override from Settings when they change.
    static let defaults: [String: Rate] = [
        // Anthropic
        "claude-opus-4": Rate(15, 75),
        "claude-sonnet-4": Rate(3, 15),
        "claude-haiku-4": Rate(1, 5),
        "claude-3-5-sonnet": Rate(3, 15),
        "claude-3-5-haiku": Rate(0.80, 4),
        "claude-3-opus": Rate(15, 75),
        "claude-3-haiku": Rate(0.25, 1.25),
        // OpenAI
        "gpt-4o-mini": Rate(0.15, 0.60),
        "gpt-4o": Rate(2.50, 10),
        "gpt-4.1-mini": Rate(0.40, 1.60),
        "gpt-4.1": Rate(2, 8),
        "gpt-4-turbo": Rate(10, 30),
        "gpt-4": Rate(30, 60),
        "o4-mini": Rate(1.10, 4.40),
        "o3-mini": Rate(1.10, 4.40),
        // Google
        "gemini-2.0-flash": Rate(0.10, 0.40),
        "gemini-1.5-flash": Rate(0.075, 0.30),
        "gemini-1.5-pro": Rate(1.25, 5),
        "gemini-pro": Rate(0.50, 1.50),
    ]

    /// Runtime overrides (e.g. from a Settings editor), merged over `defaults` and
    /// taking precedence on key collision. Injectable for tests.
    static var overrides: [String: Rate] = [:]

    /// The rate for a model, or `nil` if neither overrides nor defaults price it.
    /// Matches by longest lowercased-prefix so dated model ids resolve to a family.
    static func rate(for model: String) -> Rate? {
        let id = model.lowercased()
        let table = defaults.merging(overrides) { _, override in override }
        let match = table.keys
            .filter { id.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        return match.flatMap { table[$0] }
    }

    /// Estimated USD cost for a call, or `nil` if the model is unpriced. Zero tokens
    /// at a known rate is `0` (priced, just free), distinct from `nil` (unpriced).
    static func estimate(model: String, tokensIn: Int, tokensOut: Int) -> Double? {
        guard let rate = rate(for: model) else { return nil }
        let input = Double(max(0, tokensIn)) / 1_000_000 * rate.inputPer1M
        let output = Double(max(0, tokensOut)) / 1_000_000 * rate.outputPer1M
        return input + output
    }
}
