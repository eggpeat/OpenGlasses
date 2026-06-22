import XCTest
@testable import OpenGlasses

/// Headless tests for the Plan M3 audio-session precedence guard: a live expert call and a
/// realtime voice session can't both own the mic. The coordinator's logic is pure (the
/// pipeline side-effects + the realtime check are injected), so it's fully unit-testable.
@MainActor
final class ExpertCallPrecedenceTests: XCTestCase {

    @MainActor
    private final class StubControl: ExpertCallAudioControlling {
        var paused = 0
        var resumed = 0
        func pauseVoicePipeline() { paused += 1 }
        func resumeVoicePipeline() { resumed += 1 }
    }

    private func makeCoordinator(realtimeActive: Bool) -> (ExpertCallAudioCoordinator, StubControl) {
        let coordinator = ExpertCallAudioCoordinator()
        let control = StubControl()
        coordinator.control = control
        coordinator.isRealtimeSessionActive = { realtimeActive }
        return (coordinator, control)
    }

    func testStartsWhenNoRealtimeSession() {
        let (coordinator, control) = makeCoordinator(realtimeActive: false)
        XCTAssertFalse(coordinator.isBlockedByRealtime)
        XCTAssertEqual(coordinator.beginCall(), .started)
        XCTAssertTrue(coordinator.isCallActive)
        XCTAssertEqual(control.paused, 1)
    }

    func testBlockedByActiveRealtimeSession() {
        let (coordinator, control) = makeCoordinator(realtimeActive: true)
        XCTAssertTrue(coordinator.isBlockedByRealtime)
        XCTAssertEqual(coordinator.beginCall(), .blockedByRealtime)
        XCTAssertFalse(coordinator.isCallActive)      // pipeline untouched
        XCTAssertEqual(control.paused, 0)
    }

    func testSecondBeginIsAlreadyActive() {
        let (coordinator, _) = makeCoordinator(realtimeActive: false)
        XCTAssertEqual(coordinator.beginCall(), .started)
        XCTAssertEqual(coordinator.beginCall(), .alreadyActive)
    }

    func testEndCallResumesAndIsIdempotent() {
        let (coordinator, control) = makeCoordinator(realtimeActive: false)
        _ = coordinator.beginCall()
        coordinator.endCall()
        XCTAssertFalse(coordinator.isCallActive)
        XCTAssertEqual(control.resumed, 1)
        coordinator.endCall()                          // no-op
        XCTAssertEqual(control.resumed, 1)
    }

    func testNotBlockedWhileACallIsAlreadyActive() {
        let coordinator = ExpertCallAudioCoordinator()
        coordinator.control = StubControl()
        coordinator.isRealtimeSessionActive = { false }
        XCTAssertEqual(coordinator.beginCall(), .started)
        // A realtime session starting mid-call doesn't "block" the call that already owns the mic.
        coordinator.isRealtimeSessionActive = { true }
        XCTAssertFalse(coordinator.isBlockedByRealtime)
    }

    func testNilProviderNeverBlocks() {
        let coordinator = ExpertCallAudioCoordinator()
        coordinator.control = StubControl()
        XCTAssertFalse(coordinator.isBlockedByRealtime)
        XCTAssertEqual(coordinator.beginCall(), .started)
    }
}
