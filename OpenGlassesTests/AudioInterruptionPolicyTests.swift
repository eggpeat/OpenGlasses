import AVFoundation
import XCTest
@testable import OpenGlasses

/// Tests the pure interruption/route → recovery-action mapping that drives self-healing in the two
/// realtime audio managers. No live engine or session — just the decision logic.
final class AudioInterruptionPolicyTests: XCTestCase {

    // MARK: - Interruptions

    func testInterruptionBeganWhileCapturingPauses() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .began, shouldResume: false, isCapturing: true),
            .pause
        )
    }

    func testInterruptionBeganWhileNotCapturingDoesNothing() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .began, shouldResume: false, isCapturing: false),
            .none
        )
    }

    func testInterruptionEndedWithShouldResumeWhileCapturingResumes() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .ended, shouldResume: true, isCapturing: true),
            .resume
        )
    }

    func testInterruptionEndedWithoutShouldResumeDoesNothing() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .ended, shouldResume: false, isCapturing: true),
            .none
        )
    }

    func testInterruptionEndedWhileNotCapturingDoesNothing() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .ended, shouldResume: true, isCapturing: false),
            .none
        )
    }

    // MARK: - Route changes

    func testOldDeviceUnavailableWhileCapturingResets() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .oldDeviceUnavailable, isCapturing: true),
            .resetGraph
        )
    }

    func testNewDeviceAvailableWhileCapturingResets() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .newDeviceAvailable, isCapturing: true),
            .resetGraph
        )
    }

    func testRouteChangeWhileNotCapturingDoesNothing() {
        XCTAssertEqual(
            AudioInterruptionPolicy.action(for: .oldDeviceUnavailable, isCapturing: false),
            .none
        )
    }

    func testBenignRouteChangeReasonsDoNothing() {
        for reason: AVAudioSession.RouteChangeReason in [.categoryChange, .override, .wakeFromSleep, .routeConfigurationChange] {
            XCTAssertEqual(
                AudioInterruptionPolicy.action(for: reason, isCapturing: true),
                .none,
                "reason \(reason.rawValue) should not trigger a reset"
            )
        }
    }

    // MARK: - Resume ownership (BM P5)

    func testMayResumeOnlyWhenEngineStillOwnsTheSession() {
        // A resume after a phone call must not stomp whoever acquired the session meanwhile.
        XCTAssertTrue(AudioInterruptionPolicy.mayResume(engineOwner: .openAIRealtime, currentOwner: .openAIRealtime))
        XCTAssertTrue(AudioInterruptionPolicy.mayResume(engineOwner: .geminiLive, currentOwner: .geminiLive))
        XCTAssertFalse(AudioInterruptionPolicy.mayResume(engineOwner: .openAIRealtime, currentOwner: .wakeWord))
        XCTAssertFalse(AudioInterruptionPolicy.mayResume(engineOwner: .geminiLive, currentOwner: .openAIRealtime))
        // A released session (nobody owns it) is also not ours to reactivate.
        XCTAssertFalse(AudioInterruptionPolicy.mayResume(engineOwner: .openAIRealtime, currentOwner: nil))
    }
}
