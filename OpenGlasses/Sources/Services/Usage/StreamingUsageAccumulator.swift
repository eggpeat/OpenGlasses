import Foundation

/// Accumulates token usage across a streamed (SSE) LLM response (Plan AU follow-up).
/// The non-streaming paths read a single `usage` block; streaming splits it across
/// events — Anthropic reports input on `message_start` and a running output on each
/// `message_delta`; OpenAI-compatible servers emit a final chunk carrying `usage`
/// (only when the request asked for `stream_options.include_usage`). Pure +
/// headless-testable; the SSE reconstructors feed it each decoded event.
struct StreamingUsageAccumulator {
    private(set) var tokensIn = 0
    private(set) var tokensOut = 0

    var hasUsage: Bool { tokensIn + tokensOut > 0 }

    /// Feed one decoded Anthropic stream event.
    mutating func consumeAnthropic(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "message_start":
            if let usage = (event["message"] as? [String: Any])?["usage"] as? [String: Any] {
                tokensIn = max(tokensIn, Self.int(usage["input_tokens"]))
                tokensOut = max(tokensOut, Self.int(usage["output_tokens"]))
            }
        case "message_delta":
            // Output is cumulative across deltas — keep the largest seen.
            if let usage = event["usage"] as? [String: Any] {
                tokensOut = max(tokensOut, Self.int(usage["output_tokens"]))
            }
        default:
            break
        }
    }

    /// Feed one decoded OpenAI-compatible stream chunk. Only the final chunk (empty
    /// `choices`) carries `usage`; earlier content chunks are ignored here.
    mutating func consumeOpenAI(_ chunk: [String: Any]) {
        guard let usage = chunk["usage"] as? [String: Any] else { return }
        tokensIn = max(tokensIn, Self.int(usage["prompt_tokens"]))
        tokensOut = max(tokensOut, Self.int(usage["completion_tokens"]))
    }

    private static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        return 0
    }
}
