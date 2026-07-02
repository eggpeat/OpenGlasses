import Foundation

/// Pure reconnect decisions shared by the Gemini Live and OpenAI Realtime services
/// (docs/plans/BD-realtime-session-resilience.md). No sockets, no state — just the two decisions
/// the audit found both services getting wrong, isolated so they can be table-tested.
enum RealtimeReconnect {

    /// Backoff + give-up policy. `delay(forAttempt:)` returns the wait before a 1-based attempt, or
    /// nil once the attempt would exceed `maxAttempts` (give up).
    struct Policy {
        let maxAttempts: Int
        let maxBackoffSeconds: Double

        func delay(forAttempt attempt: Int) -> Double? {
            guard attempt >= 1, attempt <= maxAttempts else { return nil }
            return min(pow(2.0, Double(attempt - 1)), maxBackoffSeconds)
        }
    }

    /// Classify an OpenAI Realtime `error` event. A recoverable error (most commonly a
    /// `response.cancel` that raced the end of a response — "no active response") must NOT push the
    /// session into a terminal `.error` state, or the assistant goes silently deaf while the mic
    /// stays open. Only genuinely fatal errors should tear down and reconnect.
    static func isFatalOpenAIError(code: String?, message: String?) -> Bool {
        let recoverableCodes: Set<String> = [
            "response_cancel_not_active",
            "conversation_already_has_active_response",
            "input_audio_buffer_commit_empty",
        ]
        if let code = code?.lowercased(), recoverableCodes.contains(code) { return false }

        let m = (message ?? "").lowercased()
        let recoverablePhrases = [
            "no active response",
            "already has an active response",
            "cancellation failed",
            "buffer is empty",
            "no response to cancel",
        ]
        if recoverablePhrases.contains(where: m.contains) { return false }

        return true
    }
}
