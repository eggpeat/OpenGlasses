import XCTest
@testable import OpenGlasses

/// Tests `StudyService` generation + quiz/review flows via injected seams (no LLM/doc-store/clock
/// dependence), plus `study` tool routing. Headless.
@MainActor
final class StudyServiceTests: XCTestCase {

    private let genJSON: [String: Any] = [
        "summary": ["title": "Cells", "overview": "Basics.", "key_points": ["membrane"]],
        "flashcards": [["front": "What is the powerhouse?", "back": "Mitochondria"]],
        "quiz": [["prompt": "Powerhouse?", "options": ["Nucleus", "Mitochondria"], "correct_index": 1]]
    ]

    private func tempStore() -> StudyStore {
        StudyStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("study-\(UUID().uuidString)", isDirectory: true))
    }

    private func makeService() -> StudyService {
        let svc = StudyService()
        svc.store = tempStore()
        svc.clock = { 1000 }
        svc.generate = { [genJSON] _, _, _ in genJSON }
        return svc
    }

    private func deck() -> StudyDeck {
        StudyDeck(id: "d1", createdAt: Date(), source: nil,
                  summary: StudySummary(title: "T", overview: "o", keyPoints: [], docType: nil),
                  flashcards: [Flashcard(id: "f1", front: "F1", back: "B1"), Flashcard(id: "f2", front: "F2", back: "B2")],
                  quiz: [
                    QuizQuestion(id: "q1", prompt: "P1", options: [QuizOption(id: "q1o0", text: "A"), QuizOption(id: "q1o1", text: "B")], correctOptionID: "q1o0"),
                    QuizQuestion(id: "q2", prompt: "P2", options: [QuizOption(id: "q2o0", text: "C"), QuizOption(id: "q2o1", text: "D")], correctOptionID: "q2o1")
                  ])
    }

    // MARK: - Generation

    func testMakeDeckFromText() async throws {
        let svc = makeService()
        let deck = try await svc.makeDeck(fromText: "some source text", source: "src")
        XCTAssertEqual(deck.flashcards.count, 1)
        XCTAssertEqual(svc.store.decks.count, 1)
    }

    func testMakeDeckGenerationFailure() async {
        let svc = makeService()
        svc.generate = { _, _, _ in nil }
        do { _ = try await svc.makeDeck(fromText: "x", source: nil); XCTFail("expected failure") }
        catch StudyServiceError.generationFailed {} catch { XCTFail("wrong error: \(error)") }
    }

    // MARK: - Quiz flow

    func testQuizFlowAllCorrect() {
        let svc = makeService()
        svc.store.saveDeck(deck())
        XCTAssertTrue(svc.startQuiz(deckID: "d1")?.contains("Question 1 of 2") ?? false)
        XCTAssertTrue(svc.answerQuiz("1").contains("Question 2 of 2"))   // q1 correct = option 1
        let summary = svc.answerQuiz("2")                               // q2 correct = option 2
        XCTAssertTrue(summary.contains("2/2"))
        XCTAssertTrue(summary.contains("100%"))
        XCTAssertNil(svc.quizSession)
    }

    func testQuizFlowWithMiss() {
        let svc = makeService()
        svc.store.saveDeck(deck())
        _ = svc.startQuiz(deckID: "d1")
        _ = svc.answerQuiz("2")              // q1 wrong
        let summary = svc.answerQuiz("2")    // q2 correct
        XCTAssertTrue(summary.contains("1/2"))
        XCTAssertTrue(summary.contains("Review:"))
    }

    // MARK: - Review flow

    func testReviewFlowUpdatesSpacedRepetition() {
        let svc = makeService()
        svc.store.saveDeck(deck())
        XCTAssertTrue(svc.startReview(deckID: "d1")?.contains("Card 1 of 2") ?? false)
        XCTAssertEqual(svc.flip(), "B1")
        XCTAssertTrue(svc.gradeCard(correct: true).contains("Card 2 of 2"))
        _ = svc.flip()
        XCTAssertTrue(svc.gradeCard(correct: false).contains("Review complete"))
        XCTAssertEqual(svc.store.reviewRecord(cardID: "f1")?.box, 1)    // correct → promoted
        XCTAssertEqual(svc.store.reviewRecord(cardID: "f2")?.box, 0)    // miss → box 0
        XCTAssertNil(svc.reviewSession)
    }

    // MARK: - Tool

    private func isolateSharedTool() {
        StudyService.shared.store = tempStore()
        StudyService.shared.clock = { 1000 }
        StudyService.shared.generate = { [genJSON] _, _, _ in genJSON }
    }

    func testToolMakeDeckNeedsSource() async throws {
        StudyService.shared.clearScan()
        let result = try await StudyTool().execute(args: ["action": "make_deck"])
        XCTAssertTrue(result.localizedCaseInsensitiveContains("tell me what to study"))
    }

    func testToolMakeThenQuiz() async throws {
        isolateSharedTool()
        let made = try await StudyTool().execute(args: ["action": "make_deck", "text": "cells text"])
        XCTAssertTrue(made.contains("Made deck"))
        let quiz = try await StudyTool().execute(args: ["action": "quiz"])
        XCTAssertTrue(quiz.contains("Question 1"))
    }

    func testToolListEmpty() async throws {
        StudyService.shared.store = tempStore()
        let result = try await StudyTool().execute(args: ["action": "list"])
        XCTAssertTrue(result.localizedCaseInsensitiveContains("no study decks"))
    }

    // MARK: - Scan → OCR source

    func testScanIngestAccumulatesThenBuildsDeck() async throws {
        let svc = makeService()
        svc.ocr = { _ in "Cells are the basic unit of life." }
        let first = await svc.ingestScannedImage(Data([0x1]))
        XCTAssertTrue(first.contains("page 1"))
        _ = await svc.ingestScannedImage(Data([0x2]))
        XCTAssertEqual(svc.scanPages, 2)
        XCTAssertTrue(svc.hasScannedPages)
        let deck = try await svc.makeDeckFromScan()
        XCTAssertEqual(deck.source, "Scanned notes")
        XCTAssertFalse(svc.hasScannedPages)     // buffer cleared after building
    }

    func testScanEmptyOCRRejected() async {
        let svc = makeService()
        svc.ocr = { _ in "   " }
        let status = await svc.ingestScannedImage(Data([0x1]))
        XCTAssertTrue(status.localizedCaseInsensitiveContains("couldn't read"))
        XCTAssertEqual(svc.scanPages, 0)
    }

    func testMakeDeckFromEmptyScanThrows() async {
        let svc = makeService()
        do { _ = try await svc.makeDeckFromScan(); XCTFail("expected noDocument") }
        catch StudyServiceError.noDocument {} catch { XCTFail("wrong error: \(error)") }
    }

    func testToolMakeDeckFromScanBuffer() async throws {
        isolateSharedTool()
        StudyService.shared.clearScan()
        StudyService.shared.ocr = { _ in "Scanned content about mitochondria." }
        _ = await StudyService.shared.ingestScannedImage(Data([0x1]))
        let made = try await StudyTool().execute(args: ["action": "make_deck"])
        XCTAssertTrue(made.contains("Made deck"))
    }
}
