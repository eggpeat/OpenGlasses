import XCTest
@testable import OpenGlasses

/// Plan BH — deny-by-default policy for remote commands, plus the token-bucket rate limiter.
final class RemoteCommandPolicyTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func decide(
        _ command: RemoteGlassesCommand,
        agentMode: Bool = true,
        toggles: RemoteCommandPolicy.Toggles = .init(observe: true, output: true, capture: true),
        rateState: inout RemoteInvokeRateState,
        at time: Date? = nil
    ) -> RemoteCommandPolicy.Decision {
        RemoteCommandPolicy.decide(
            command: command, agentModeEnabled: agentMode, toggles: toggles,
            rateState: &rateState, now: time ?? t0)
    }

    // MARK: - Agent Mode gate

    func testAgentModeOffDeniesEverythingIncludingHalt() {
        var rate = RemoteInvokeRateState(now: t0)
        let everything: [RemoteGlassesCommand] = [
            .deviceStatus, .speak(text: "hi"), .capturePhoto, .stopAll,
        ]
        for command in everything {
            XCTAssertEqual(decide(command, agentMode: false, rateState: &rate),
                           .deny(.agentModeOff), "\(command) must deny with Agent Mode off")
        }
    }

    // MARK: - Class toggles

    func testDefaultTogglesDenyCaptureButAllowObserveAndOutput() {
        var rate = RemoteInvokeRateState(now: t0)
        let defaults = RemoteCommandPolicy.Toggles.defaults
        XCTAssertEqual(decide(.deviceStatus, toggles: defaults, rateState: &rate), .allow)
        XCTAssertEqual(decide(.speak(text: "hi"), toggles: defaults, rateState: &rate), .allow)
        XCTAssertEqual(decide(.capturePhoto, toggles: defaults, rateState: &rate),
                       .deny(.classDisabled(.capture)),
                       "capture is the surveillance class and must default off")
    }

    func testEachClassToggleGatesItsOwnClassOnly() {
        var rate = RemoteInvokeRateState(now: t0)
        let observeOff = RemoteCommandPolicy.Toggles(observe: false, output: true, capture: true)
        XCTAssertEqual(decide(.getTranscript, toggles: observeOff, rateState: &rate),
                       .deny(.classDisabled(.observe)))
        XCTAssertEqual(decide(.displayClear, toggles: observeOff, rateState: &rate), .allow)

        let outputOff = RemoteCommandPolicy.Toggles(observe: true, output: false, capture: true)
        XCTAssertEqual(decide(.speak(text: "x"), toggles: outputOff, rateState: &rate),
                       .deny(.classDisabled(.output)))
    }

    func testHaltBypassesAllClassToggles() {
        var rate = RemoteInvokeRateState(now: t0)
        let allOff = RemoteCommandPolicy.Toggles(observe: false, output: false, capture: false)
        XCTAssertEqual(decide(.stopAll, toggles: allOff, rateState: &rate), .allow,
                       "a remote agent may always STOP activity while Agent Mode is on")
        XCTAssertEqual(decide(.stopVideo, toggles: allOff, rateState: &rate), .allow)
    }

    // MARK: - Rate limiting

    func testCaptureBurstIsTightAndRefills() {
        var rate = RemoteInvokeRateState(now: t0)
        // Capture bucket: capacity 2.
        XCTAssertEqual(decide(.capturePhoto, rateState: &rate), .allow)
        XCTAssertEqual(decide(.capturePhoto, rateState: &rate), .allow)
        XCTAssertEqual(decide(.capturePhoto, rateState: &rate),
                       .deny(.rateLimited(.capture)))
        // 4/min refill → one token after 15 s.
        XCTAssertEqual(decide(.capturePhoto, rateState: &rate, at: t0.addingTimeInterval(15)), .allow)
        XCTAssertEqual(decide(.capturePhoto, rateState: &rate, at: t0.addingTimeInterval(15)),
                       .deny(.rateLimited(.capture)))
    }

    func testClassesHaveIndependentBuckets() {
        var rate = RemoteInvokeRateState(now: t0)
        // Exhaust capture...
        _ = decide(.capturePhoto, rateState: &rate)
        _ = decide(.capturePhoto, rateState: &rate)
        XCTAssertEqual(decide(.capturePhoto, rateState: &rate), .deny(.rateLimited(.capture)))
        // ...observe still flows.
        XCTAssertEqual(decide(.deviceStatus, rateState: &rate), .allow)
    }

    func testTokenBucketNeverExceedsCapacityAfterLongIdle() {
        var bucket = TokenBucket(capacity: 2, refillPerSecond: 1, now: t0)
        XCTAssertTrue(bucket.tryConsume(now: t0))
        XCTAssertTrue(bucket.tryConsume(now: t0))
        XCTAssertFalse(bucket.tryConsume(now: t0))
        // An hour later the bucket holds `capacity`, not 3600 tokens.
        let later = t0.addingTimeInterval(3600)
        XCTAssertTrue(bucket.tryConsume(now: later))
        XCTAssertTrue(bucket.tryConsume(now: later))
        XCTAssertFalse(bucket.tryConsume(now: later))
    }

    func testTokenBucketToleratesBackwardsClock() {
        var bucket = TokenBucket(capacity: 1, refillPerSecond: 1, now: t0)
        XCTAssertTrue(bucket.tryConsume(now: t0))
        // Clock jumps backwards — no crash, no negative refill, still empty.
        XCTAssertFalse(bucket.tryConsume(now: t0.addingTimeInterval(-60)))
    }

    // MARK: - Structured deny reasons

    func testDenyReasonsCarryStableCodes() {
        XCTAssertEqual(RemoteCommandPolicy.DenyReason.agentModeOff.code, "denied.agent_mode_off")
        XCTAssertEqual(RemoteCommandPolicy.DenyReason.classDisabled(.capture).code,
                       "denied.class_disabled.capture")
        XCTAssertEqual(RemoteCommandPolicy.DenyReason.rateLimited(.output).code,
                       "denied.rate_limited.output")
    }
}
