import XCTest
@testable import OpenGlasses

/// Tests `StudyAnswerMatcher` (docs/plans/study-mode.md): number/ordinal/letter/text matching of a
/// spoken answer to a quiz option. Pure/headless.
final class StudyAnswerMatcherTests: XCTestCase {

    private let options = [
        QuizOption(id: "o0", text: "Chloroplast"),
        QuizOption(id: "o1", text: "Mitochondria"),
        QuizOption(id: "o2", text: "Nucleus")
    ]

    func testMatchesByNumberWord() {
        XCTAssertEqual(StudyAnswerMatcher.match("option two", options: options)?.id, "o1")
        XCTAssertEqual(StudyAnswerMatcher.match("the second one", options: options)?.id, "o1")
    }

    func testMatchesByDigit() {
        XCTAssertEqual(StudyAnswerMatcher.match("1", options: options)?.id, "o0")
        XCTAssertEqual(StudyAnswerMatcher.match("answer 3", options: options)?.id, "o2")
    }

    func testMatchesByLetter() {
        XCTAssertEqual(StudyAnswerMatcher.match("b", options: options)?.id, "o1")
    }

    func testMatchesByText() {
        XCTAssertEqual(StudyAnswerMatcher.match("chloroplast", options: options)?.id, "o0")
        XCTAssertEqual(StudyAnswerMatcher.match("it's the mitochondria", options: options)?.id, "o1")
    }

    func testNoMatch() {
        XCTAssertNil(StudyAnswerMatcher.match("completely unrelated zzz", options: options))
        XCTAssertNil(StudyAnswerMatcher.match("", options: options))
        XCTAssertNil(StudyAnswerMatcher.match("5", options: options))   // out of range
    }
}
