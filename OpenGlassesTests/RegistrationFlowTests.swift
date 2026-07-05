import XCTest
@testable import OpenGlasses

/// The Meta-registration wait policy: the registered threshold, actionable status text, and a
/// deadline long enough for the real Meta AI approval round-trip.
final class RegistrationFlowTests: XCTestCase {

    func testRegisteredThreshold() {
        XCTAssertFalse(RegistrationFlow.isRegistered(stateRaw: 0))
        XCTAssertFalse(RegistrationFlow.isRegistered(stateRaw: 2))
        XCTAssertTrue(RegistrationFlow.isRegistered(stateRaw: 3))
        XCTAssertTrue(RegistrationFlow.isRegistered(stateRaw: 4))
    }

    func testStatusTellsTheUserWhatToDoWhileWaiting() {
        let waiting = RegistrationFlow.status(stateRaw: 2)
        XCTAssertTrue(waiting.contains("Meta AI"), "the blocked state is fixed in the Meta AI app — say so")
        XCTAssertFalse(waiting.contains("state"), "never surface a raw internal state number")
        XCTAssertFalse(waiting.contains(where: \.isNumber), "no digits in the user-facing status")
    }

    func testStatusOnceRegistered() {
        XCTAssertEqual(RegistrationFlow.status(stateRaw: 3), "Waiting for device…")
        XCTAssertEqual(RegistrationFlow.status(stateRaw: 4), "Waiting for device…")
    }

    func testDeadlineCoversTheObservedApprovalLatency() {
        XCTAssertGreaterThanOrEqual(RegistrationFlow.approvalDeadlineSeconds, 25,
            "Meta AI approval has been observed to take ~25s; the old 10s deadline gave up too early")
    }
}
