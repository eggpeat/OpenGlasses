import Foundation

/// Pure extraction of token usage from the realtime voice sessions (Plan AU follow-up).
/// OpenAI Realtime reports **per-response** usage on `response.done`; Gemini Live reports
/// **cumulative** session totals in `usageMetadata`. Headless-testable; the session
/// managers feed it each decoded server message and record the result via `UsageTracker`.
enum RealtimeUsage {

    /// OpenAI Realtime `response.done` → that response's `(input, output)` tokens, or nil.
    static func openAIResponseUsage(_ event: [String: Any]) -> (tokensIn: Int, tokensOut: Int)? {
        guard let usage = (event["response"] as? [String: Any])?["usage"] as? [String: Any] else { return nil }
        let tIn = int(usage["input_tokens"])
        let tOut = int(usage["output_tokens"])
        return (tIn + tOut > 0) ? (tIn, tOut) : nil
    }

    /// Gemini Live `usageMetadata` → the **cumulative** `(input, output)` totals so far, or nil.
    /// Output prefers `responseTokenCount`, falling back to `candidatesTokenCount`.
    static func geminiCumulative(_ message: [String: Any]) -> (tokensIn: Int, tokensOut: Int)? {
        guard let meta = message["usageMetadata"] as? [String: Any] else { return nil }
        let tIn = int(meta["promptTokenCount"])
        let tOut = meta["responseTokenCount"] != nil ? int(meta["responseTokenCount"])
                                                      : int(meta["candidatesTokenCount"])
        return (tIn + tOut > 0) ? (tIn, tOut) : nil
    }

    private static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        return 0
    }
}

/// Converts a stream of **cumulative** usage totals (Gemini Live) into the per-update
/// delta to record, so a growing session total isn't double-counted. Pure value type.
struct CumulativeUsageMeter {
    private var lastIn = 0
    private var lastOut = 0

    /// The newly-added `(input, output)` since the last cumulative reading. Never negative
    /// (a reset or lower reading yields 0 for that component).
    mutating func delta(tokensIn: Int, tokensOut: Int) -> (tokensIn: Int, tokensOut: Int) {
        let dIn = max(0, tokensIn - lastIn)
        let dOut = max(0, tokensOut - lastOut)
        if tokensIn >= lastIn { lastIn = tokensIn }
        if tokensOut >= lastOut { lastOut = tokensOut }
        return (dIn, dOut)
    }
}
