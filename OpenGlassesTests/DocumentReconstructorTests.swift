import XCTest
@testable import OpenGlasses

/// Headless tests for `DocumentReconstructor` — rebuilding readable text from the chunker's
/// overlapping chunks (the teleprompter Document-RAG source). Pure: no DB, no embeddings.
final class DocumentReconstructorTests: XCTestCase {

    func testDeOverlapRemovesRepeatedRun() {
        // The chunker repeats trailing words/sentences into the next chunk.
        let chunks = [
            "The museum opens at nine. Tickets are twelve dollars.",
            "Tickets are twelve dollars. Guided tours run hourly.",
        ]
        let text = DocumentReconstructor.deOverlap(chunks)
        XCTAssertEqual(text, "The museum opens at nine. Tickets are twelve dollars. Guided tours run hourly.")
        // The overlapping sentence appears exactly once.
        XCTAssertEqual(text.components(separatedBy: "Tickets are twelve dollars").count - 1, 1)
    }

    func testDeOverlapNoOverlapConcatenates() {
        XCTAssertEqual(DocumentReconstructor.deOverlap(["alpha beta", "gamma delta"]),
                       "alpha beta gamma delta")
    }

    func testDeOverlapHandlesEmptyAndSingle() {
        XCTAssertEqual(DocumentReconstructor.deOverlap([]), "")
        XCTAssertEqual(DocumentReconstructor.deOverlap(["just one chunk"]), "just one chunk")
    }

    func testDeOverlapTakesLargestMatch() {
        // Full first chunk repeated as the prefix of the second → only the tail is appended.
        let chunks = ["one two three", "one two three four five"]
        XCTAssertEqual(DocumentReconstructor.deOverlap(chunks), "one two three four five")
    }

    func testScriptLinesBreaksOnSentenceEnders() {
        let lines = DocumentReconstructor.scriptLines("First sentence. Second one! A third?  Trailing")
        XCTAssertEqual(lines, "First sentence.\nSecond one!\nA third?\nTrailing")
    }

    func testScriptTextEndToEnd() {
        let chunks = ["Welcome to the demo. Please hold questions.",
                      "Please hold questions. We begin shortly."]
        let script = DocumentReconstructor.scriptText(fromOrderedChunks: chunks)
        XCTAssertEqual(script, "Welcome to the demo.\nPlease hold questions.\nWe begin shortly.")
        // Parses into a multi-line teleprompter script (so the paginator can scroll it).
        let parsed = TeleprompterScript.parse(title: "Doc", text: script)
        XCTAssertEqual(parsed.lines.count, 3)
        XCTAssertGreaterThan(parsed.wordCount, 0)
    }
}
