import XCTest
@testable import OpenGlasses

/// Headless tests for the pure teleprompter core (Phase 1): tokenizer, speech→position
/// aligner, paginator, and live speed. No UI, no hardware — this is the audio-paced brain.
final class TeleprompterCoreTests: XCTestCase {

    // MARK: - Parse / normalize

    func testParseTokenizesAndTracksLines() {
        let s = TeleprompterScript.parse(title: "Demo", text: "Hello, world!\n\nSecond line here")
        XCTAssertEqual(s.title, "Demo")
        XCTAssertEqual(s.tokens.map(\.normalized), ["hello", "world", "second", "line", "here"])
        XCTAssertEqual(s.tokens.first?.line, 0)
        XCTAssertEqual(s.tokens.last?.line, 2)   // blank line sits at index 1
        XCTAssertEqual(s.wordCount, 5)
    }

    func testNormalizeStripsPunctuationAndCase() {
        XCTAssertEqual(TeleprompterText.normalize("Hello,"), "hello")
        XCTAssertEqual(TeleprompterText.normalize("Don't"), "dont")
        XCTAssertEqual(TeleprompterText.normalize("$20!"), "20")
        XCTAssertEqual(TeleprompterText.normalize("—"), "")
    }

    func testEmptyTitleFallsBack() {
        XCTAssertEqual(TeleprompterScript.parse(title: "   ", text: "hi").title, "Script")
    }

    // MARK: - Aligner

    private let script = ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]

    func testFirstWordAdvances() {
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 0, heard: ["the"]), 1)
    }

    func testInOrderSpeechTracksPosition() {
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 1, heard: ["the", "quick"]), 2)
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 2, heard: ["the", "quick", "brown"]), 3)
    }

    func testParaphraseWithinFuzzyToleranceMatches() {
        // "brown" misheard as "browns" — edit distance 1 / 6 = 0.83 ≥ 0.8, still matches.
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 2, heard: ["quick", "browns"]), 3)
    }

    func testSkippedAheadJumpsForward() {
        // Speaker jumped to "lazy dog" (positions 7,8) from cursor 2 — corroborated, so jump.
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 2, heard: ["lazy", "dog"]), 9)
    }

    func testOffScriptHolds() {
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 3, heard: ["banana", "split"]), 3)
    }

    func testLonePauseHolds() {
        // Last heard word is "brown" (pos 2); cursor already at 3 → no forward motion.
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 3, heard: ["quick", "brown"]), 3)
    }

    func testNoSpuriousBackwardJump() {
        // A single weak "quick" (only at pos 1) must not drag the cursor back from 6.
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 6, heard: ["quick"]), 6)
    }

    func testRepeatedWordDoesNotDoubleAdvance() {
        let after = ScriptAligner.advance(script: script, cursor: 2, heard: ["the", "quick", "brown"])
        XCTAssertEqual(after, 3)
        // Saying "brown" again should not push past "fox".
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: after, heard: ["quick", "brown", "brown"]), 3)
    }

    func testEndOfScriptClamps() {
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 8, heard: ["lazy", "dog"]), 9)
        XCTAssertLessThanOrEqual(ScriptAligner.advance(script: script, cursor: 9, heard: ["dog"]), 9)
    }

    func testEmptyHeardHolds() {
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 4, heard: []), 4)
        XCTAssertEqual(ScriptAligner.advance(script: script, cursor: 4, heard: [""]), 4)
    }

    func testFuzzyEqualShortWordsRequireExact() {
        XCTAssertTrue(ScriptAligner.fuzzyEqual("to", "to", 0.8))
        XCTAssertFalse(ScriptAligner.fuzzyEqual("to", "do", 0.8))   // length 2 → exact only
        XCTAssertTrue(ScriptAligner.fuzzyEqual("colour", "color", 0.8))
    }

    // MARK: - PacingSpeed

    func testPacingSpeedClampsAndNudges() {
        var s = PacingSpeed(wpm: 1000, leadLines: 99, responsiveness: 5)
        XCTAssertEqual(s.wpm, 240)
        XCTAssertEqual(s.leadLines, 4)
        XCTAssertEqual(s.responsiveness, 1.0, accuracy: 0.0001)

        s.nudgeWPM(-10_000)
        XCTAssertEqual(s.wpm, 60)
        s.setWPM(120)
        XCTAssertEqual(s.secondsPerWord, 0.5, accuracy: 0.0001)
    }

    // MARK: - Paginator

    func testWindowShowsActiveLineForward() {
        let text = "Line one alpha\nLine two beta\nLine three gamma\nLine four delta"
        let s = TeleprompterScript.parse(title: "t", text: text)
        let idx = s.tokens.firstIndex { $0.normalized == "two" }!
        let w = TeleprompterPaginator.window(s, cursor: idx,
                                             geometry: .init(maxLines: 2, maxChars: 40))
        XCTAssertEqual(w.lines, ["Line two beta", "Line three gamma"])
        XCTAssertEqual(w.activeLineIndex, 0)
        XCTAssertGreaterThan(w.progress, 0)
        XCTAssertLessThan(w.progress, 1)
    }

    func testWindowSkipsBlankLines() {
        let s = TeleprompterScript.parse(title: "t", text: "alpha\n\nbeta")
        let idx = s.tokens.firstIndex { $0.normalized == "alpha" }!
        let w = TeleprompterPaginator.window(s, cursor: idx,
                                             geometry: .init(maxLines: 2, maxChars: 40))
        XCTAssertEqual(w.lines, ["alpha", "beta"])   // blank line collapsed
    }

    func testWrapLongLine() {
        let wrapped = TeleprompterPaginator.wrap("one two three four five", maxChars: 9)
        XCTAssertTrue(wrapped.allSatisfy { $0.count <= 9 })
        XCTAssertEqual(wrapped.joined(separator: " "), "one two three four five")
    }

    func testWrapHardSplitsOverlongWord() {
        let wrapped = TeleprompterPaginator.wrap("supercalifragilistic", maxChars: 6)
        XCTAssertTrue(wrapped.allSatisfy { $0.count <= 6 })
        XCTAssertEqual(wrapped.joined(), "supercalifragilistic")
    }

    func testProgressReachesOneAtEnd() {
        let s = TeleprompterScript.parse(title: "t", text: "a b c")
        XCTAssertEqual(TeleprompterPaginator.window(s, cursor: 3).progress, 1.0, accuracy: 0.0001)
    }
}
