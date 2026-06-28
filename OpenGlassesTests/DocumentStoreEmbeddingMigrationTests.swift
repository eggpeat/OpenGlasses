import XCTest
@testable import OpenGlasses

/// Integration tests for the embedding version stamp on `DocumentStore`: chunks are stamped on
/// ingest, an invalidated (model-changed) stamp is re-embedded and re-stamped on query (lazy
/// self-heal) and via `reindexOutdated` (eager). Skipped when no on-device embedding model is
/// available (the migration needs to actually embed text).
@MainActor
final class DocumentStoreEmbeddingMigrationTests: XCTestCase {

    private func makeStore() -> DocumentStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return DocumentStore(directory: dir)
    }

    private let manual = """
    To reset the thermostat, hold the power button for ten seconds until the screen blinks.
    For Wi-Fi setup, open the companion app and select Add Device from the main menu.
    Battery replacement requires a Phillips screwdriver and two AA cells.
    """

    private func requireModel() throws {
        try XCTSkipUnless(Embedder().isAvailable, "No on-device embedding model on this host")
    }

    func testChunksStampedOnIngest() async throws {
        try requireModel()
        let store = makeStore()
        await store.ingest(name: "Manual", text: manual)
        XCTAssertEqual(store.outdatedChunkCount, 0, "freshly-ingested chunks carry the current stamp")
    }

    func testInvalidateMarksAllOutdated() async throws {
        try requireModel()
        let store = makeStore()
        await store.ingest(name: "Manual", text: manual)
        XCTAssertEqual(store.outdatedChunkCount, 0)

        store.invalidateEmbeddings()
        XCTAssertGreaterThan(store.outdatedChunkCount, 0, "clearing stamps marks every chunk outdated")
    }

    func testQueryLazilyReEmbedsAndReStamps() async throws {
        try requireModel()
        let store = makeStore()
        await store.ingest(name: "Manual", text: manual)
        store.invalidateEmbeddings()                                  // simulate a model change
        XCTAssertGreaterThan(store.outdatedChunkCount, 0)

        // A query must still return results (lazy re-embed), not go empty after invalidation…
        let hits = store.query("how do I reset the thermostat", limit: 3)
        XCTAssertFalse(hits.isEmpty, "query self-heals outdated chunks instead of returning nothing")
        // …and the chunks it touched are now re-stamped to the current model.
        XCTAssertEqual(store.outdatedChunkCount, 0, "queried chunks were re-embedded and re-stamped")
    }

    func testReindexOutdatedReembedsEverything() async throws {
        try requireModel()
        let store = makeStore()
        await store.ingest(name: "Manual", text: manual)
        store.invalidateEmbeddings()
        let outdated = store.outdatedChunkCount
        XCTAssertGreaterThan(outdated, 0)

        let count = await store.reindexOutdated()
        XCTAssertEqual(count, outdated, "every outdated chunk re-embedded")
        XCTAssertEqual(store.outdatedChunkCount, 0)
    }

    func testCurrentVersionTagMatchesEmbedder() throws {
        try requireModel()
        let store = makeStore()
        XCTAssertEqual(store.currentEmbeddingVersionTag, Embedder().version.tag)
    }
}
