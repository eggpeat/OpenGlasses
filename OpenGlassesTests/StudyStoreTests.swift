import XCTest
@testable import OpenGlasses

/// Tests `StudyStore` persistence (docs/plans/study-mode.md): decks newest-first, get/delete, review
/// records, and reload-from-disk. Temp directory. Headless.
@MainActor
final class StudyStoreTests: XCTestCase {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("study-\(UUID().uuidString)", isDirectory: true)
    }

    private func deck(_ id: String) -> StudyDeck {
        StudyDeck(id: id, createdAt: Date(), source: "doc",
                  summary: StudySummary(title: "T", overview: "o", keyPoints: [], docType: nil),
                  flashcards: [Flashcard(id: "\(id)-f1", front: "q", back: "a")], quiz: [])
    }

    func testSaveGetDeleteDecks() {
        let store = StudyStore(directory: tempDir())
        store.saveDeck(deck("a"))
        store.saveDeck(deck("b"))
        XCTAssertEqual(store.decks.map(\.id), ["b", "a"])     // newest first
        XCTAssertNotNil(store.deck(id: "a"))
        store.deleteDeck(id: "a")
        XCTAssertNil(store.deck(id: "a"))
        XCTAssertEqual(store.decks.map(\.id), ["b"])
    }

    func testReloadPersistsDecksAndReviews() {
        let dir = tempDir()
        let store = StudyStore(directory: dir)
        store.saveDeck(deck("a"))
        store.saveReviewRecord(ReviewRecord(cardID: "a-f1", box: 2, dueAt: 500, lastReviewed: 100))

        let reloaded = StudyStore(directory: dir)
        XCTAssertEqual(reloaded.decks.map(\.id), ["a"])
        XCTAssertEqual(reloaded.reviewRecord(cardID: "a-f1")?.box, 2)
        XCTAssertEqual(reloaded.allReviewRecords.count, 1)
    }
}
