import XCTest
@testable import OpenGlasses

/// Headless tests for the embedding version-stamp substrate: the `EmbeddingVersion` value, its
/// tag round-trip, and the pure migration policy. No model, no store.
final class EmbeddingVersionTests: XCTestCase {

    // MARK: - Tag round-trip

    func testTagFormat() {
        XCTAssertEqual(EmbeddingVersion(modelId: "nl-word.en", dim: 300).tag, "nl-word.en#300")
    }

    func testTagRoundTrip() {
        let v = EmbeddingVersion(modelId: "minilm-l6-v2", dim: 384)
        XCTAssertEqual(EmbeddingVersion(tag: v.tag), v)
    }

    func testTagParseRejectsMalformed() {
        XCTAssertNil(EmbeddingVersion(tag: nil))
        XCTAssertNil(EmbeddingVersion(tag: ""))
        XCTAssertNil(EmbeddingVersion(tag: "no-dim"))          // no '#'
        XCTAssertNil(EmbeddingVersion(tag: "model#notanint"))  // non-integer dim
        XCTAssertNil(EmbeddingVersion(tag: "#300"))            // empty model id
    }

    func testTagParseToleratesHashInModelId() {
        // lastIndex(of:"#") means a '#' inside the id is fine — only the final segment is the dim.
        let v = EmbeddingVersion(tag: "weird#id#128")
        XCTAssertEqual(v, EmbeddingVersion(modelId: "weird#id", dim: 128))
    }

    // MARK: - Compatibility

    func testCompatibleOnlyWhenIdentical() {
        let cur = EmbeddingVersion(modelId: "nl-contextual.en", dim: 512)
        XCTAssertTrue(EmbeddingMigrationPolicy.isCompatible(stored: cur, current: cur))
        XCTAssertFalse(EmbeddingMigrationPolicy.isCompatible(
            stored: EmbeddingVersion(modelId: "nl-word.en", dim: 512), current: cur))   // diff model
        XCTAssertFalse(EmbeddingMigrationPolicy.isCompatible(
            stored: EmbeddingVersion(modelId: "nl-contextual.en", dim: 300), current: cur)) // diff dim
    }

    func testUnstampedIsNeverCompatible() {
        let cur = EmbeddingVersion(modelId: "nl-word.en", dim: 300)
        XCTAssertFalse(EmbeddingMigrationPolicy.isCompatible(stored: nil, current: cur))
    }

    // MARK: - Migration action

    func testActionReuseOnMatchReembedOtherwise() {
        let cur = EmbeddingVersion(modelId: "nl-sentence.en", dim: 512)
        XCTAssertEqual(EmbeddingMigrationPolicy.action(stored: cur, current: cur), .reuse)
        XCTAssertEqual(EmbeddingMigrationPolicy.action(stored: nil, current: cur), .reembed)
        XCTAssertEqual(
            EmbeddingMigrationPolicy.action(
                stored: EmbeddingVersion(modelId: "nl-word.en", dim: 300), current: cur),
            .reembed)
    }

    // MARK: - Embedder exposes a stamp

    func testEmbedderModelIdShape() {
        let e = Embedder(language: .english)
        // Model availability varies by host, but the id is always well-formed and language-tagged.
        XCTAssertTrue(e.modelId.hasPrefix("nl-"), "got \(e.modelId)")
        XCTAssertTrue(e.modelId.hasSuffix(".en"), "got \(e.modelId)")
        XCTAssertEqual(e.version.modelId, e.modelId)
        XCTAssertEqual(e.version.dim, e.dimension)
    }
}
