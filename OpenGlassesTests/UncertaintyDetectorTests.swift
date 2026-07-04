import XCTest
@testable import OpenGlasses

/// Plan BI — the pure uncertainty gate for local-backend answers: epistemic hedging in the
/// answer, or a freshness-sensitive question, trips a web-grounded re-ask.
final class UncertaintyDetectorTests: XCTestCase {

    // MARK: - Hedged answers

    func testEpistemicHedgesTrip() {
        let hedges = [
            "I'm not sure about that.",
            "I don't know the answer to that one.",
            "As of my last update, the CEO was...",
            "I don't have access to real-time information.",
            "My training data only goes up to 2024.",
            "I can't browse the internet, but generally speaking...",
            "I'm unable to access current market data.",
        ]
        for answer in hedges {
            let verdict = UncertaintyDetector.assess(question: "Who is the CEO of Acme?", answer: answer)
            XCTAssertTrue(verdict.shouldSearch, "should trip on: \(answer)")
            XCTAssertEqual(verdict.reason, .hedged)
        }
    }

    func testCurlyApostrophesAndCaseAreNormalized() {
        let verdict = UncertaintyDetector.assess(
            question: "Who wrote Dune?",
            answer: "I\u{2019}M NOT SURE, but it might be Frank Herbert.")
        XCTAssertTrue(verdict.shouldSearch)
    }

    func testPoliteNonEpistemicNotSureDoesNotTrip() {
        // "not sure" without the first-person epistemic anchor is conversational politeness,
        // not an admission of ignorance.
        let verdict = UncertaintyDetector.assess(
            question: "Play me something relaxing",
            answer: "Not sure if you'd like jazz, but this playlist is a calm one.")
        XCTAssertEqual(verdict, .confident)
    }

    func testConfidentEvergreenAnswerDoesNotTrip() {
        let verdict = UncertaintyDetector.assess(
            question: "Who wrote Pride and Prejudice?",
            answer: "Pride and Prejudice was written by Jane Austen, published in 1813.")
        XCTAssertEqual(verdict, .confident)
    }

    // MARK: - Freshness-sensitive questions

    func testFreshQuestionsTripEvenWithConfidentAnswers() {
        let questions = [
            "What's the latest iPhone?",
            "Who won the game today?",
            "What's the current price of bitcoin?",
            "How much is a Tesla Model 3?",
            "Any news on the election this week?",
            "What's the score right now?",
        ]
        for question in questions {
            let verdict = UncertaintyDetector.assess(
                question: question,
                answer: "It's definitely X, no doubt about it.")
            XCTAssertTrue(verdict.shouldSearch, "should trip on: \(question)")
            XCTAssertEqual(verdict.reason, .freshnessRequested,
                           "a confident stale answer is the worst case — freshness must fire on the question")
        }
    }

    func testFreshnessWinsTheReasonWhenBothSignalsTrip() {
        let verdict = UncertaintyDetector.assess(
            question: "What's the latest Swift version?",
            answer: "I'm not sure, my training data may be out of date.")
        XCTAssertEqual(verdict.reason, .freshnessRequested)
    }

    func testFreshnessMarkersRespectWordBoundaries() {
        // "underscore" must not fire "score"; "recurrent" must not fire "current".
        XCTAssertEqual(UncertaintyDetector.assess(
            question: "How do I type an underscore in Vim?",
            answer: "Press shift-minus.").shouldSearch, false)
        XCTAssertEqual(UncertaintyDetector.assess(
            question: "Explain recurrent neural networks",
            answer: "An RNN processes sequences...").shouldSearch, false)
    }

    func testEvergreenQuestionWithConfidentAnswerStaysLocal() {
        let verdict = UncertaintyDetector.assess(
            question: "What is the capital of France?",
            answer: "The capital of France is Paris.")
        XCTAssertEqual(verdict, .confident)
    }

    // MARK: - Config flag

    func testFallbackFlagDefaultsOn() {
        UserDefaults.standard.removeObject(forKey: "localWebSearchFallbackEnabled")
        XCTAssertTrue(Config.localWebSearchFallbackEnabled,
                      "the gate should be on out of the box — DuckDuckGo needs no key")
    }
}
