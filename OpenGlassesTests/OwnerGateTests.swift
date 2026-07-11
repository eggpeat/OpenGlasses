import XCTest
@testable import OpenGlasses

/// BM P10 — the owner gate on Simple-Mode exit (and optional Settings entry): the pure state
/// machine and applicability policy. The `LAContext` prompt is the thin edge.
final class OwnerGateTests: XCTestCase {

    // MARK: - State machine

    func testBeginOnlyFromLocked() {
        var gate = OwnerGateMachine()
        XCTAssertEqual(gate.state, .locked)
        XCTAssertTrue(gate.begin())
        XCTAssertEqual(gate.state, .authenticating)
        XCTAssertFalse(gate.begin(), "no double-prompting while an attempt is in flight")

        gate.finish(success: true)
        XCTAssertEqual(gate.state, .unlocked)
        XCTAssertFalse(gate.begin(), "an existing grant needs no new prompt")
    }

    func testFinishSuccessUnlocksFailureRelocks() {
        var gate = OwnerGateMachine()
        _ = gate.begin()
        gate.finish(success: false)
        XCTAssertEqual(gate.state, .locked)
        XCTAssertTrue(gate.lastFailed)

        XCTAssertTrue(gate.begin(), "a failed attempt allows a retry")
        XCTAssertFalse(gate.lastFailed, "starting a retry clears the failure flag")
        gate.finish(success: true)
        XCTAssertEqual(gate.state, .unlocked)
        XCTAssertFalse(gate.lastFailed)
    }

    func testStaleFinishIgnoredUnlessAuthenticating() {
        var gate = OwnerGateMachine()
        gate.finish(success: true)
        XCTAssertEqual(gate.state, .locked, "a stale callback can't unlock a gate that never asked")

        _ = gate.begin()
        gate.finish(success: true)
        gate.finish(success: false)
        XCTAssertEqual(gate.state, .unlocked, "a late failure can't revoke a delivered grant")
        XCTAssertFalse(gate.lastFailed)
    }

    func testGrantIsSingleUse() {
        var gate = OwnerGateMachine()
        _ = gate.begin()
        gate.finish(success: true)

        XCTAssertTrue(gate.consume())
        XCTAssertEqual(gate.state, .locked, "consuming relocks — the next exit needs fresh auth")
        XCTAssertFalse(gate.consume(), "a grant can't be spent twice")
    }

    func testConsumeWithoutGrantFails() {
        var gate = OwnerGateMachine()
        XCTAssertFalse(gate.consume())
        _ = gate.begin()
        XCTAssertFalse(gate.consume(), "in-flight auth is not a grant")
        XCTAssertEqual(gate.state, .authenticating, "a failed consume doesn't disturb the attempt")
    }

    func testRelockClearsEverything() {
        var gate = OwnerGateMachine()
        _ = gate.begin()
        gate.finish(success: false)
        gate.relock()
        XCTAssertEqual(gate.state, .locked)
        XCTAssertFalse(gate.lastFailed)
    }

    // MARK: - Policy

    func testOnlySimpleModeExitRequiresGate() {
        // Leaving Simple Mode (re-exposing the owner surface) → gate.
        XCTAssertTrue(OwnerGatePolicy.requiresGate(togglingSimpleModeTo: false, currentlyEnabled: true))
        // Entering it (locking down before a hand-off) → free.
        XCTAssertFalse(OwnerGatePolicy.requiresGate(togglingSimpleModeTo: true, currentlyEnabled: false))
        // Re-asserting the current value is a no-op either way.
        XCTAssertFalse(OwnerGatePolicy.requiresGate(togglingSimpleModeTo: true, currentlyEnabled: true))
        XCTAssertFalse(OwnerGatePolicy.requiresGate(togglingSimpleModeTo: false, currentlyEnabled: false))
    }

    func testGateFailsOpenWithoutDeviceAuth() {
        // No passcode set: the gate can't be stronger than the device — grant rather than
        // permanently lock the owner out.
        XCTAssertTrue(OwnerGatePolicy.grantWithoutPrompt(authAvailable: false))
        XCTAssertFalse(OwnerGatePolicy.grantWithoutPrompt(authAvailable: true))
    }

    // MARK: - Simple-Mode exit flow (machine + policy composed, as the view drives them)

    func testSimpleModeExitRequiresAGrant() {
        var gate = OwnerGateMachine()
        var simpleModeEnabled = true

        // Denied auth → no exit.
        XCTAssertTrue(OwnerGatePolicy.requiresGate(togglingSimpleModeTo: false, currentlyEnabled: simpleModeEnabled))
        XCTAssertTrue(gate.begin())
        gate.finish(success: false)
        if gate.consume() { simpleModeEnabled = false }
        XCTAssertTrue(simpleModeEnabled, "a denied grant must not exit Simple Mode")
        XCTAssertTrue(gate.lastFailed)

        // Granted auth → exit, and the grant is spent.
        XCTAssertTrue(gate.begin())
        gate.finish(success: true)
        if gate.consume() { simpleModeEnabled = false }
        XCTAssertFalse(simpleModeEnabled)
        XCTAssertEqual(gate.state, .locked, "re-entering and re-exiting later needs fresh auth")
    }
}
