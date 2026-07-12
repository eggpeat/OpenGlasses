import AVFoundation
import XCTest
@testable import OpenGlasses

/// BJ PR1 — the off-main activation seam. A recording `AudioSessionConforming` fake drives the
/// coordinator with no live `AVAudioSession`, so the activation order, the failure rollback, the
/// no-deactivate/no-fallback `reconfigure` contract, and the superseded-deactivation race are
/// asserted rather than reasoned about.
final class AudioSessionCoordinatorTests: XCTestCase {

    /// Records every session call in order, plus the thread each `setActive` ran on. Injectable
    /// failures for `setCategory` / activation.
    final class FakeAudioSession: AudioSessionConforming, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [String] = []
        private(set) var categories: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = []
        private(set) var setActiveOnMainThread: [Bool] = []
        var currentRoutePortTypes: [AVAudioSession.Port] = []

        var setCategoryError: Error?
        /// Thrown from `setActive(true, …)` only (an activation failure).
        var activateError: Error?

        private func record(_ s: String) { lock.lock(); calls.append(s); lock.unlock() }

        func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                         options: AVAudioSession.CategoryOptions) throws {
            record("setCategory")
            lock.lock(); categories.append((category, mode, options)); lock.unlock()
            if let setCategoryError { throw setCategoryError }
        }
        func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
            record("setActive(\(active))")
            lock.lock(); setActiveOnMainThread.append(Thread.isMainThread); lock.unlock()
            if active, let activateError { throw activateError }
        }
        func overrideOutputAudioPort(_ port: AVAudioSession.PortOverride) throws { record("override") }
        func setPreferredSampleRate(_ sampleRate: Double) throws { record("rate") }
        func setPreferredIOBufferDuration(_ duration: TimeInterval) throws { record("buffer") }

        var containsDeactivate: Bool { lock.lock(); defer { lock.unlock() }; return calls.contains("setActive(false)") }
    }

    // MARK: - Activation runs off the caller's (main) thread

    @MainActor
    func testAcquireOffMainRunsActivationOffTheMainThread() async throws {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)
        _ = try await coord.acquireOffMain(.transcription, category: .playAndRecord, mode: .default, options: [])
        XCTAssertFalse(fake.setActiveOnMainThread.isEmpty, "activation happened")
        XCTAssertTrue(fake.setActiveOnMainThread.allSatisfy { $0 == false },
                      "all setActive calls run on sessionIOQueue, never the main (caller) thread")
    }

    // MARK: - setCategory before setActive; verbatim passthrough

    func testAcquireConfiguresCategoryBeforeActivatingAndPassesArgsVerbatim() throws {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)
        _ = try coord.acquire(.wakeWord, category: .record, mode: .measurement, options: [.mixWithOthers])
        // Order: deactivate-first (from the activator's stale-route clear), setCategory, setActive.
        XCTAssertEqual(fake.calls, ["setActive(false)", "setCategory", "setActive(true)"])
        let (cat, mode, opts) = try XCTUnwrap(fake.categories.first)
        XCTAssertEqual(cat, .record)
        XCTAssertEqual(mode, .measurement)
        XCTAssertEqual(opts, [.mixWithOthers])
    }

    // MARK: - Failed activation rolls the lease back through the coordinator

    func testFailedActivationRollsLeaseBack() async {
        let fake = FakeAudioSession()
        fake.activateError = AudioSessionError.activationFailed("nope")
        let coord = AudioSessionCoordinator(session: fake)
        do {
            _ = try await coord.acquireOffMain(.geminiLive, category: .playAndRecord, mode: .voiceChat, options: [])
            XCTFail("expected activation to throw")
        } catch {
            XCTAssertNil(coord.currentOwner, "a failed acquire must not leave the caller recorded as owner")
        }
    }

    // MARK: - reconfigure: no deactivate-first, no fallback

    func testReconfigureNeverDeactivatesFirst() async throws {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)
        try await coord.reconfigure(category: .playAndRecord, mode: .default, options: [.mixWithOthers])
        XCTAssertEqual(fake.calls, ["setCategory", "setActive(true)"],
                       "reconfigure re-tunes in place: no deactivate-first, just setCategory then setActive")
    }

    func testReconfigureDoesNotFallBackToDefaultOnFailure() async {
        let fake = FakeAudioSession()
        fake.setCategoryError = AudioSessionError.activationFailed("route busy")
        let coord = AudioSessionCoordinator(session: fake)
        do {
            try await coord.reconfigure(category: .playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
            XCTFail("expected the failure to surface")
        } catch {
            XCTAssertEqual(fake.calls, ["setCategory"],
                           "no silent .default fallback — a single attempt, then the error surfaces")
        }
    }

    // MARK: - Superseded deactivation is suppressed (the race)

    func testSupersededDeactivationIsSuppressed() async {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)

        let a = coord.assumeOwnership(.wakeWord)          // A owns (self-activated, no session call)
        let gate = DispatchSemaphore(value: 0)
        coord.sessionIOQueue.async { gate.wait() }        // hold the IO queue so ordering is deterministic
        coord.release(a)                                  // queues A's deactivation behind the held block
        _ = coord.assumeOwnership(.geminiLive)            // B acquires before the deactivation can run
        gate.signal()                                     // let the IO queue drain
        await coord.activationSettled()                   // wait for the (suppressed) deactivation block

        XCTAssertFalse(fake.containsDeactivate,
                       "a deactivation superseded by a newer owner must not tear down the live session")
        XCTAssertEqual(coord.currentOwner, .geminiLive)
    }

    /// Sanity: an un-superseded release *does* deactivate.
    func testUnsupersededReleaseDeactivates() async {
        let fake = FakeAudioSession()
        let coord = AudioSessionCoordinator(session: fake)
        let a = coord.assumeOwnership(.wakeWord)
        coord.release(a)
        await coord.activationSettled()
        XCTAssertTrue(fake.containsDeactivate, "the sole owner's release deactivates the session")
        XCTAssertNil(coord.currentOwner)
    }
}
