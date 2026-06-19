import XCTest
@testable import OpenGlasses

/// Tests `StudyContentBuilder.parse` (docs/plans/study-mode.md): mapping model JSON → `StudyDeck`,
/// dropping invalid MCQs, and requiring ≥1 usable flashcard. Headless.
final class StudyContentBuilderTests: XCTestCase {

    private let fixture: [String: Any] = [
        "summary": ["title": "Photosynthesis", "overview": "How plants make food.",
                    "key_points": ["light", "chlorophyll"], "doc_type": "biology notes"],
        "flashcards": [
            ["front": "What is photosynthesis?", "back": "Converting light to chemical energy."],
            ["front": "", "back": "dropped — empty front"]
        ],
        "quiz": [
            ["prompt": "Where does it occur?", "options": ["Chloroplast", "Mitochondria", "Nucleus"], "correct_index": 0],
            ["prompt": "too few options", "options": ["only one"], "correct_index": 0],     // dropped
            ["prompt": "index out of range", "options": ["a", "b"], "correct_index": 5]      // dropped
        ]
    ]

    func testParsesValidContentAndDropsBadCards() throws {
        let deck = try StudyContentBuilder.parse(fixture, id: "d1", createdAt: Date(timeIntervalSinceReferenceDate: 0), source: "bio")
        XCTAssertEqual(deck.summary.title, "Photosynthesis")
        XCTAssertEqual(deck.summary.keyPoints, ["light", "chlorophyll"])
        XCTAssertEqual(deck.flashcards.count, 1)                      // empty-front card dropped
        XCTAssertEqual(deck.quiz.count, 1)                           // two invalid MCQs dropped
        let q = deck.quiz[0]
        XCTAssertEqual(q.options.count, 3)
        XCTAssertEqual(q.correctOption?.text, "Chloroplast")
    }

    func testNoFlashcardsThrows() {
        let json: [String: Any] = ["summary": ["title": "x", "overview": "y"], "flashcards": [], "quiz": []]
        XCTAssertThrowsError(try StudyContentBuilder.parse(json)) { error in
            guard case StudyContentBuilder.StudyError.noFlashcards = error else {
                return XCTFail("expected noFlashcards, got \(error)")
            }
        }
    }

    func testSummaryDefaultsWhenMissing() throws {
        let json: [String: Any] = ["flashcards": [["front": "q", "back": "a"]]]
        let deck = try StudyContentBuilder.parse(json)
        XCTAssertEqual(deck.summary.title, "Study deck")             // default
        XCTAssertTrue(deck.quiz.isEmpty)
    }

    func testSchemaConstrainsShape() {
        let schema = StudyContentBuilder.jsonSchema()
        let required = schema["required"] as? [String]
        XCTAssertEqual(Set(required ?? []), ["summary", "flashcards", "quiz"])
    }
}
