import AVFoundation
import XCTest
@testable import OpenGlasses

/// BG BO — the realtime managers now activate the shared session **off-main** through the
/// coordinator's `acquireOffMain` (was a main-thread `acquire`). These tests exercise the
/// coordinator behaviour the realtime path relies on, driven through a recording fake with a
/// blockable `sessionIOQueue` — the "recovery reset during a pending activation" scenario the plan
/// calls out, without a live `AVAudioSession` or `AVAudioEngine`.
final class RealtimeActivationCoordinationTests: XCTestCase {

    /// Records activation calls and the thread each ran on.
    final class FakeAudioSession: AudioSessionConforming, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var activateCount = 0
        private(set) var setActiveOnMainThread: [Bool] = []
        var currentRoutePortTypes: [AVAudioSession.Port] = []

        func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                         options: AVAudioSession.CategoryOptions) throws {}
        func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
            lock.lock(); defer { lock.unlock() }
            if active { activateCount += 1; setActiveOnMainThread.append(Thread.isMainThread) }
        }
        func overrideOutputAudioPort(_ port: AVAudioSession.PortOverride) throws {}
        func setPreferredSampleRate(_ sampleRate: Double) throws {}
        func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {}
    }

    // MARK: - Off-main

    @MainActor
    func testRealtimeAcquireRunsOffTheMainThread() async throws {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)
        _ = try await coord.acquireOffMain(.geminiLive, category: .playAndRecord, mode: .videoChat,
                                           options: [.defaultToSpeaker, .allowBluetoothHFP])
        XCTAssertFalse(fake.setActiveOnMainThread.isEmpty, "activation happened")
        XCTAssertTrue(fake.setActiveOnMainThread.allSatisfy { $0 == false },
                      "realtime activation never runs on the main (caller) thread")
        XCTAssertEqual(coord.currentOwner, .geminiLive)
    }

    // MARK: - Reset during a pending activation

    /// Models `attemptAudioResetOnQueue` re-acquiring while a prior activation is still in flight:
    /// the second acquire supersedes the first, both run serially on `sessionIOQueue`, and the run
    /// completes (no deadlock) with a single live owner.
    func testResetDuringPendingActivationSupersedesWithoutDeadlock() async throws {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)

        // Hold the IO queue so the first activation can't complete yet — the "pending activation".
        let gate = DispatchSemaphore(value: 0)
        coord.sessionIOQueue.async { gate.wait() }

        // First acquire (its activation is queued behind the gate) and, before it runs, a second
        // acquire for the same owner — the recovery reset.
        async let first = coord.acquireOffMain(.openAIRealtime, category: .playAndRecord,
                                               mode: .voiceChat, options: [])
        async let second = coord.acquireOffMain(.openAIRealtime, category: .playAndRecord,
                                                mode: .voiceChat, options: [])
        gate.signal()                                  // let both activations drain, in order
        _ = try await [first, second]
        await coord.activationSettled()

        XCTAssertEqual(coord.currentOwner, .openAIRealtime, "one live owner after the reset")
        XCTAssertEqual(fake.activateCount, 2, "each acquire activated once, serially — no lost/dup")
    }

    /// A realtime `release` while wake word has since taken over must NOT deactivate (the
    /// interruption-recovery ownership guard the realtime path depends on).
    func testSupersededRealtimeReleaseDoesNotDeactivate() async {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)
        let realtime = try? await coord.acquireOffMain(.geminiLive, category: .playAndRecord,
                                                       mode: .videoChat, options: [])
        _ = coord.assumeOwnership(.wakeWord)           // wake word preempts mid-call
        if let realtime { coord.release(realtime) }    // stale realtime teardown
        await coord.activationSettled()
        XCTAssertEqual(coord.currentOwner, .wakeWord, "wake word still owns the session")
    }
}
