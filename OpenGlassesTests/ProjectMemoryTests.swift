import XCTest
@testable import OpenGlasses

/// Headless tests for project-scoped memory: the pure scope/formatter, the `BrainStore` round-trip,
/// and the pure user-memory fact selector. No model, no UI, no field session.
final class ProjectMemoryTests: XCTestCase {

    private func mem(_ tag: String, _ text: String, _ t: TimeInterval) -> ProjectMemory {
        ProjectMemory(projectTag: tag, text: text, createdAt: Date(timeIntervalSince1970: t))
    }

    // MARK: - ProjectMemoryScope

    func testScopeReturnsOnlyActiveProjectRecords() {
        let records = [mem("job-1", "a", 1), mem("job-2", "b", 2), mem("job-1", "c", 3)]
        let eligible = ProjectMemoryScope.eligible(records, activeProject: "job-1")
        XCTAssertEqual(eligible.map(\.text), ["a", "c"])
    }

    func testScopeEmptyWhenNoActiveProject() {
        let records = [mem("job-1", "a", 1)]
        XCTAssertTrue(ProjectMemoryScope.eligible(records, activeProject: nil).isEmpty)
        XCTAssertTrue(ProjectMemoryScope.eligible(records, activeProject: "  ").isEmpty)
    }

    func testScopeNoBleedAcrossProjects() {
        let records = [mem("job-1", "a", 1), mem("job-2", "b", 2)]
        XCTAssertEqual(ProjectMemoryScope.eligible(records, activeProject: "job-2").map(\.text), ["b"])
    }

    // MARK: - ProjectMemoryFormatter

    func testFormatterEmptyForNoRecords() {
        XCTAssertEqual(ProjectMemoryFormatter.block([]), "")
    }

    func testFormatterOrdersOldestFirstUnderOneHeading() {
        let records = [mem("j", "second", 20), mem("j", "first", 10), mem("j", "third", 30)]
        let block = ProjectMemoryFormatter.block(records)
        XCTAssertTrue(block.hasPrefix("CURRENT PROJECT"))
        let body = block.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(body, ["- first", "- second", "- third"])
    }

    // MARK: - BrainStore project memory store

    @MainActor
    func testBrainStoreProjectMemoryRoundTripAndScoping() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjMemTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BrainStore(directory: dir)

        store.addProjectMemory(projectTag: "job-1", text: "compressor swap next")
        store.addProjectMemory(projectTag: "job-1", text: "customer wants a quote")
        store.addProjectMemory(projectTag: "job-2", text: "different job")

        let job1 = store.projectMemories(for: "job-1")
        XCTAssertEqual(job1.map(\.text), ["compressor swap next", "customer wants a quote"])  // oldest first
        XCTAssertEqual(store.projectMemories(for: "job-2").count, 1)
        XCTAssertTrue(store.projectMemories(for: "unknown").isEmpty)

        store.clearProjectMemories(for: "job-1")
        XCTAssertTrue(store.projectMemories(for: "job-1").isEmpty)
        XCTAssertEqual(store.projectMemories(for: "job-2").count, 1, "Clearing one job leaves others intact")
    }

    @MainActor
    func testBrainStoreRejectsBlankProjectMemory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjMemTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BrainStore(directory: dir)

        store.addProjectMemory(projectTag: "job", text: "   ")
        store.addProjectMemory(projectTag: "  ", text: "real text")
        XCTAssertTrue(store.projectMemories(for: "job").isEmpty)
    }
}
