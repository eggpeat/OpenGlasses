import XCTest
@testable import OpenGlasses

/// Tests the pure "single owner" arbitration for the shared `AVAudioSession`. The decisive
/// property is stale-release suppression: a preempted owner releasing must NOT deactivate the
/// session a newer owner now holds.
final class AudioSessionLedgerTests: XCTestCase {

    private let tokenA = UUID()
    private let tokenB = UUID()

    func testAcquireOnFreeSessionHasNoPreemptedLease() {
        var ledger = AudioSessionLedger()
        let result = ledger.acquire(.wakeWord, token: tokenA)
        XCTAssertNil(result.preempted)
        XCTAssertEqual(result.lease.owner, .wakeWord)
        XCTAssertEqual(result.lease.generation, 1)
        XCTAssertEqual(ledger.current, result.lease)
    }

    func testSecondAcquirePreemptsFirstAndBumpsGeneration() {
        var ledger = AudioSessionLedger()
        let first = ledger.acquire(.wakeWord, token: tokenA).lease
        let second = ledger.acquire(.geminiLive, token: tokenB)
        XCTAssertEqual(second.preempted, first)
        XCTAssertEqual(second.lease.owner, .geminiLive)
        XCTAssertGreaterThan(second.lease.generation, first.generation)
        XCTAssertEqual(ledger.current, second.lease)
    }

    func testReleasingCurrentLeaseDeactivatesAndFreesSession() {
        var ledger = AudioSessionLedger()
        let lease = ledger.acquire(.geminiLive, token: tokenA).lease
        XCTAssertEqual(ledger.release(lease), .deactivate)
        XCTAssertNil(ledger.current)
    }

    func testStaleReleaseAfterPreemptionIsSuppressed() {
        var ledger = AudioSessionLedger()
        let old = ledger.acquire(.geminiLive, token: tokenA).lease
        let new = ledger.acquire(.openAIRealtime, token: tokenB).lease
        // The preempted owner's late teardown must not deactivate the new owner's session.
        XCTAssertEqual(ledger.release(old), .superseded(by: .openAIRealtime))
        XCTAssertEqual(ledger.current, new, "the newer lease must still own the session")
    }

    func testReleaseWhenNobodyHoldsIsAlreadyReleased() {
        var ledger = AudioSessionLedger()
        let lease = ledger.acquire(.wakeWord, token: tokenA).lease
        _ = ledger.release(lease)
        XCTAssertEqual(ledger.release(lease), .alreadyReleased)
    }

    func testDoubleReleaseOfSameLeaseDeactivatesOnceThenIsNoOp() {
        var ledger = AudioSessionLedger()
        let lease = ledger.acquire(.geminiLive, token: tokenA).lease
        XCTAssertEqual(ledger.release(lease), .deactivate)
        XCTAssertEqual(ledger.release(lease), .alreadyReleased)
    }

    func testGenerationIsMonotonicAcrossAcquires() {
        var ledger = AudioSessionLedger()
        let g1 = ledger.acquire(.wakeWord, token: UUID()).lease.generation
        let g2 = ledger.acquire(.wakeWord, token: UUID()).lease.generation
        let g3 = ledger.acquire(.geminiLive, token: UUID()).lease.generation
        XCTAssertEqual([g1, g2, g3], [1, 2, 3])
    }

    func testReacquireBySameOwnerSupersedesItsOwnEarlierLease() {
        var ledger = AudioSessionLedger()
        let first = ledger.acquire(.geminiLive, token: tokenA).lease
        let second = ledger.acquire(.geminiLive, token: tokenB).lease
        // The first lease (e.g. before an interruption reset) is now stale even for the same owner.
        XCTAssertEqual(ledger.release(first), .superseded(by: .geminiLive))
        XCTAssertEqual(ledger.current, second)
        XCTAssertEqual(ledger.release(second), .deactivate)
    }
}
