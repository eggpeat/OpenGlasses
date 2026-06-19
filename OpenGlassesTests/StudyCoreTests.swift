import XCTest
@testable import OpenGlasses

/// Tests the Study Mode pure core (docs/plans/study-mode.md): `QuizGrader`, `SpacedRepetition` (Leitner),
/// and `StudyDeck` codable round-trip. Headless — no LLM, no clock dependence (clock injected).
final class StudyCoreTests: XCTestCase {

    private func quiz() -> [QuizQuestion] {
        [
            QuizQuestion(id: "q1", prompt: "P1",
                         options: [QuizOption(id: "a", text: "A"), QuizOption(id: "b", text: "B")],
                         correctOptionID: "a"),
            QuizQuestion(id: "q2", prompt: "P2",
                         options: [QuizOption(id: "c", text: "C"), QuizOption(id: "d", text: "D")],
                         correctOptionID: "d")
        ]
    }

    // MARK: - QuizGrader

    func testGradeAllCorrect() {
        let r = QuizGrader().grade(quiz(), answers: ["q1": "a", "q2": "d"])
        XCTAssertEqual(r.correct, 2)
        XCTAssertEqual(r.percentage, 100, accuracy: 0.0001)
        XCTAssertTrue(r.missed.isEmpty)
    }

    func testGradeMixed() {
        let r = QuizGrader().grade(quiz(), answers: ["q1": "a", "q2": "c"])
        XCTAssertEqual(r.correct, 1)
        XCTAssertEqual(r.percentage, 50, accuracy: 0.0001)
        XCTAssertEqual(r.missed.map(\.id), ["q2"])
    }

    func testGradeEmptyQuiz() {
        let r = QuizGrader().grade([], answers: [:])
        XCTAssertEqual(r.total, 0)
        XCTAssertEqual(r.percentage, 0, accuracy: 0.0001)
    }

    // MARK: - SpacedRepetition

    func testNewRecordIsBoxZeroDueNow() {
        let r = SpacedRepetition().newRecord(cardID: "c", now: 1000)
        XCTAssertEqual(r.box, 0)
        XCTAssertEqual(r.dueAt, 1000, accuracy: 0.0001)
    }

    func testCorrectPromotesAndPushesDueOut() {
        let sr = SpacedRepetition()
        let r1 = sr.update(sr.newRecord(cardID: "c", now: 1000), correct: true, now: 2000)
        XCTAssertEqual(r1.box, 1)
        XCTAssertEqual(r1.dueAt, 2000 + 86_400, accuracy: 0.0001)
    }

    func testMissResetsToBoxZeroDueNow() {
        let sr = SpacedRepetition()
        let high = ReviewRecord(cardID: "c", box: 3, dueAt: 0, lastReviewed: 0)
        let r = sr.update(high, correct: false, now: 3000)
        XCTAssertEqual(r.box, 0)
        XCTAssertEqual(r.dueAt, 3000, accuracy: 0.0001)
    }

    func testCorrectCapsAtMaxBox() {
        let sr = SpacedRepetition()
        let top = ReviewRecord(cardID: "c", box: sr.maxBox, dueAt: 0, lastReviewed: 0)
        XCTAssertEqual(sr.update(top, correct: true, now: 0).box, sr.maxBox)
    }

    func testDueOrderAndDueFilter() {
        let sr = SpacedRepetition()
        let a = ReviewRecord(cardID: "a", box: 0, dueAt: 300, lastReviewed: 0)
        let b = ReviewRecord(cardID: "b", box: 0, dueAt: 100, lastReviewed: 0)
        let c = ReviewRecord(cardID: "c", box: 0, dueAt: 200, lastReviewed: 0)
        XCTAssertEqual(sr.dueOrder([a, b, c], now: 0).map(\.cardID), ["b", "c", "a"])
        XCTAssertEqual(sr.due([a, b, c], now: 150).map(\.cardID), ["b"])
    }

    // MARK: - Codable

    func testDeckRoundTrip() throws {
        let deck = StudyDeck(
            id: "d1", createdAt: Date(timeIntervalSinceReferenceDate: 123), source: "notes",
            summary: StudySummary(title: "T", overview: "o", keyPoints: ["k"], docType: "notes"),
            flashcards: [Flashcard(id: "f1", front: "q", back: "a")],
            quiz: quiz())
        let data = try JSONEncoder().encode(deck)
        XCTAssertEqual(try JSONDecoder().decode(StudyDeck.self, from: data), deck)
    }
}
