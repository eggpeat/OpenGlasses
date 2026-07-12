import XCTest
@testable import OpenGlasses

/// BK P2(c) — the memory block injected into the system prompt must stay bounded so it can't
/// silently balloon the on-device prompt past budget as the store grows. Every branch caps the
/// number of entries and clamps per-value length; here we exercise the global-fallback and gateway
/// paths (no embedder / no query — the branch that previously dumped the whole store) plus the
/// per-value clamp. Headless: a temp-dir store, no model.
@MainActor
final class MemoryInjectionBoundsTests: XCTestCase {

    private func makeStore() -> SemanticMemoryStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SemanticMemoryStore(directory: dir)
    }

    private func bulletLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    }

    func testGlobalFallbackBranchIsCappedNotDumped() {
        let store = makeStore()
        for i in 0..<20 { store.rememberGlobal("fact\(i)", value: "value \(i)") }
        // query: nil ⇒ the sorted global fallback branch that used to inject the entire store.
        let context = store.systemPromptContext(query: nil) ?? ""
        XCTAssertLessThanOrEqual(bulletLines(context).count, SemanticMemoryStore.maxMemoryLines,
                                 "global memory must be capped, not dumped wholesale")
    }

    func testGatewayMemoriesAreCapped() {
        let store = makeStore()
        store.gatewayMemories = (0..<20).map { "gateway fact \($0)" }
        let context = store.systemPromptContext(query: nil) ?? ""
        XCTAssertLessThanOrEqual(bulletLines(context).count, SemanticMemoryStore.maxMemoryLines)
    }

    func testLongValueIsClamped() {
        let store = makeStore()
        let huge = String(repeating: "x", count: 500)
        store.rememberGlobal("bio", value: huge)
        let context = store.systemPromptContext(query: nil) ?? ""
        XCTAssertFalse(context.contains(huge), "the full over-length value must not be injected")
        XCTAssertTrue(context.contains("…"), "an over-length value is truncated with an ellipsis")
        // No injected value line exceeds the clamp (+ ellipsis + bullet scaffolding).
        for line in bulletLines(context) {
            XCTAssertLessThanOrEqual(line.count, SemanticMemoryStore.maxValueChars + 20)
        }
    }
}
