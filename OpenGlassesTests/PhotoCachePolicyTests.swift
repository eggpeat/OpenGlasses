import XCTest
@testable import OpenGlasses

/// Headless tests for the Plan T photo disk-pressure cap: the pure eviction policy and the
/// queue prune that applies it to delivered photo evidence.
final class PhotoCachePolicyTests: XCTestCase {

    private func entry(_ id: String, _ size: Int, _ t: TimeInterval) -> PhotoCachePolicy.Entry {
        PhotoCachePolicy.Entry(id: id, sizeBytes: size, createdAt: Date(timeIntervalSince1970: t))
    }

    func testNoEvictionWhenUnderBudget() {
        let entries = [entry("a", 100, 1), entry("b", 100, 2)]
        XCTAssertEqual(PhotoCachePolicy.evictions(entries, maxBytes: 500), [])
        XCTAssertEqual(PhotoCachePolicy.evictions(entries, maxBytes: 200), [])   // exactly at budget
    }

    func testEvictsOldestFirstUntilUnderBudget() {
        let entries = [entry("new", 100, 3), entry("old", 100, 1), entry("mid", 100, 2)]
        // total 300, budget 150 → drop oldest two (old, mid).
        XCTAssertEqual(PhotoCachePolicy.evictions(entries, maxBytes: 150), ["old", "mid"])
    }

    func testEvictsAllWhenBudgetZero() {
        let entries = [entry("a", 50, 1), entry("b", 50, 2)]
        XCTAssertEqual(Set(PhotoCachePolicy.evictions(entries, maxBytes: 0)), ["a", "b"])
    }

    // MARK: - Queue integration

    @MainActor
    func testPrunePhotoEvidenceDeletesOldestDeliveredFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tphoto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = OfflineQueue(path: dir.appendingPathComponent("q.sqlite"))

        func photoOp(_ name: String, bytes: Int, at t: TimeInterval, state: OpState) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data(count: bytes).write(to: url)
            let payload = try JSONSerialization.data(withJSONObject: ["path": url.path])
            queue.enqueue(QueuedOp(kind: .photoUpload, sessionId: "s", payload: payload,
                                   createdAt: Date(timeIntervalSince1970: t), state: state))
            return url
        }

        let old = try photoOp("old.jpg", bytes: 100, at: 1, state: .done)
        let mid = try photoOp("mid.jpg", bytes: 100, at: 2, state: .done)
        let new = try photoOp("new.jpg", bytes: 100, at: 3, state: .done)
        let pendingPhoto = try photoOp("pending.jpg", bytes: 100, at: 0, state: .pending)

        let freed = queue.prunePhotoEvidence(maxBytes: 150)   // keep ~newest 150 bytes of delivered

        XCTAssertEqual(freed, 200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mid.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingPhoto.path))   // pending never evicted
        // The two evicted tombstones are gone; the delivered survivor + pending remain.
        XCTAssertEqual(queue.all().filter { $0.kind == .photoUpload }.count, 2)
    }
}
