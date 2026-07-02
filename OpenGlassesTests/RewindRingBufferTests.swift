import XCTest
@testable import OpenGlasses

/// Tests for the Memory Rewind rolling window (RewindRingBuffer): the fixed-capacity ring that
/// replaced the O(n)-per-append `Data.removeFirst` design.
final class RewindRingBufferTests: XCTestCase {

    private func bytes(_ values: [UInt8]) -> Data { Data(values) }

    func testAppendAndSnapshotUnderCapacity() {
        let ring = RewindRingBuffer(capacity: 10)
        ring.append(bytes([1, 2, 3]))
        XCTAssertEqual(ring.count, 3)
        XCTAssertEqual(Array(ring.snapshotSuffix(10)), [1, 2, 3])
        XCTAssertEqual(Array(ring.snapshotSuffix(2)), [2, 3], "suffix returns the newest bytes")
    }

    func testOverwritesOldestWhenFull() {
        let ring = RewindRingBuffer(capacity: 4)
        ring.append(bytes([1, 2, 3, 4]))
        ring.append(bytes([5, 6]))          // pushes out 1, 2
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(Array(ring.snapshotSuffix(4)), [3, 4, 5, 6])
    }

    func testAppendSpanningWrapPreservesOrder() {
        let ring = RewindRingBuffer(capacity: 5)
        ring.append(bytes([1, 2, 3]))
        ring.append(bytes([4, 5, 6, 7]))    // wraps; keeps last 5: 3,4,5,6,7
        XCTAssertEqual(Array(ring.snapshotSuffix(5)), [3, 4, 5, 6, 7])
        XCTAssertEqual(Array(ring.snapshotSuffix(2)), [6, 7])
    }

    func testChunkLargerThanCapacityKeepsTail() {
        let ring = RewindRingBuffer(capacity: 3)
        ring.append(bytes([1, 2, 3, 4, 5, 6, 7]))
        XCTAssertEqual(ring.count, 3)
        XCTAssertEqual(Array(ring.snapshotSuffix(3)), [5, 6, 7])
    }

    func testSnapshotMoreThanHeldReturnsAll() {
        let ring = RewindRingBuffer(capacity: 8)
        ring.append(bytes([9, 8, 7]))
        XCTAssertEqual(Array(ring.snapshotSuffix(100)), [9, 8, 7])
    }

    func testResetClears() {
        let ring = RewindRingBuffer(capacity: 4)
        ring.append(bytes([1, 2, 3]))
        ring.reset()
        XCTAssertEqual(ring.count, 0)
        XCTAssertTrue(ring.snapshotSuffix(4).isEmpty)
    }

    func testZeroCapacityIsSafe() {
        let ring = RewindRingBuffer(capacity: 0)
        ring.append(bytes([1, 2, 3]))
        XCTAssertEqual(ring.count, 0)
        XCTAssertTrue(ring.snapshotSuffix(1).isEmpty)
    }

    func testManyWrapsStayConsistent() {
        // Continuously overwrite; the snapshot must always be the last `capacity` bytes appended.
        let ring = RewindRingBuffer(capacity: 6)
        var expected: [UInt8] = []
        for i in 0..<200 {
            let b = UInt8(i % 256)
            ring.append(bytes([b]))
            expected.append(b)
            if expected.count > 6 { expected.removeFirst(expected.count - 6) }
        }
        XCTAssertEqual(Array(ring.snapshotSuffix(6)), expected)
    }

    func testConcurrentAppendsDoNotCrash() {
        // The ring is written from the audio thread and read from the main actor — exercise both
        // under contention (TSAN regression guard).
        let ring = RewindRingBuffer(capacity: 1024)
        let writeExp = expectation(description: "writes")
        let readExp = expectation(description: "reads")
        DispatchQueue.global().async {
            for i in 0..<5000 { ring.append(Data([UInt8(i % 256)])) }
            writeExp.fulfill()
        }
        DispatchQueue.global().async {
            for _ in 0..<5000 { _ = ring.snapshotSuffix(128) }
            readExp.fulfill()
        }
        wait(for: [writeExp, readExp], timeout: 10)
        XCTAssertEqual(ring.count, 1024)
    }
}
