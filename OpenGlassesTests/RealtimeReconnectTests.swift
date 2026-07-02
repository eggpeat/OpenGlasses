import XCTest
@testable import OpenGlasses

/// Plan BD (docs/plans/BD-realtime-session-resilience.md): the pure reconnect policy + the
/// fatal-vs-recoverable OpenAI error classifier. (The socket wiring that consumes these — goAway →
/// reconnect, connect-timeout reschedule, counter reset — is device-pending by house style.)
final class RealtimeReconnectTests: XCTestCase {

    // MARK: - Policy

    func testBackoffIsExponentialAndCapped() {
        let policy = RealtimeReconnect.Policy(maxAttempts: 10, maxBackoffSeconds: 30)
        XCTAssertEqual(policy.delay(forAttempt: 1), 1)
        XCTAssertEqual(policy.delay(forAttempt: 2), 2)
        XCTAssertEqual(policy.delay(forAttempt: 3), 4)
        XCTAssertEqual(policy.delay(forAttempt: 4), 8)
        XCTAssertEqual(policy.delay(forAttempt: 6), 30, "capped at maxBackoffSeconds")
        XCTAssertEqual(policy.delay(forAttempt: 10), 30)
    }

    func testGivesUpPastMaxAttempts() {
        let policy = RealtimeReconnect.Policy(maxAttempts: 3, maxBackoffSeconds: 30)
        XCTAssertNotNil(policy.delay(forAttempt: 3))
        XCTAssertNil(policy.delay(forAttempt: 4), "attempt beyond the max should give up")
        XCTAssertNil(policy.delay(forAttempt: 0), "attempt 0 is invalid")
    }

    // MARK: - OpenAI error classification

    func testResponseCancelRaceIsRecoverable() {
        // The app's own client-VAD response.cancel racing the end of a response.
        XCTAssertFalse(RealtimeReconnect.isFatalOpenAIError(
            code: "response_cancel_not_active", message: "Cancellation failed: no active response"))
        XCTAssertFalse(RealtimeReconnect.isFatalOpenAIError(
            code: nil, message: "Error: no active response to cancel"))
    }

    func testActiveResponseConflictIsRecoverable() {
        XCTAssertFalse(RealtimeReconnect.isFatalOpenAIError(
            code: "conversation_already_has_active_response",
            message: "Conversation already has an active response"))
    }

    func testGenuineErrorsAreFatal() {
        XCTAssertTrue(RealtimeReconnect.isFatalOpenAIError(code: "invalid_api_key", message: "Invalid API key"))
        XCTAssertTrue(RealtimeReconnect.isFatalOpenAIError(code: nil, message: "Internal server error"))
        XCTAssertTrue(RealtimeReconnect.isFatalOpenAIError(code: nil, message: nil),
                      "an unclassifiable error should be treated as fatal, not silently ignored")
    }

    func testClassifierIsCaseInsensitive() {
        XCTAssertFalse(RealtimeReconnect.isFatalOpenAIError(
            code: "RESPONSE_CANCEL_NOT_ACTIVE", message: "NO ACTIVE RESPONSE"))
    }
}
