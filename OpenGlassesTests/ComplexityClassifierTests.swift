import XCTest
@testable import OpenGlasses

final class ComplexityClassifierTests: XCTestCase {

    // MARK: - decide() truth table

    func testDecideCombinesHeuristicAndLLM() {
        XCTAssertEqual(ComplexityClassifier.decide(heuristic: true, llmVerdict: nil), .multiStep)
        XCTAssertEqual(ComplexityClassifier.decide(heuristic: false, llmVerdict: true), .multiStep)
        XCTAssertEqual(ComplexityClassifier.decide(heuristic: false, llmVerdict: false), .singleShot)
        XCTAssertEqual(ComplexityClassifier.decide(heuristic: false, llmVerdict: nil), .singleShot)
        // The LLM can add recall but cannot veto a heuristic positive.
        XCTAssertEqual(ComplexityClassifier.decide(heuristic: true, llmVerdict: false), .multiStep)
    }

    // MARK: - shouldConsultLLM gating

    func testDoesNotConsultWhenHeuristicAlreadyPositive() {
        // Clear multi-step → heuristic decides, no round-trip.
        XCTAssertFalse(ComplexityClassifier.shouldConsultLLM("take a photo and then email it to Sam"))
    }

    func testDoesNotConsultPlainChat() {
        XCTAssertFalse(ComplexityClassifier.shouldConsultLLM("what's the weather today?"))
        XCTAssertFalse(ComplexityClassifier.shouldConsultLLM("hello there"))
    }

    func testConsultsAmbiguousMultiActionRequest() {
        // Two action cues but no sequencer word → ambiguous middle worth an LLM check.
        XCTAssertTrue(ComplexityClassifier.shouldConsultLLM("photograph the receipt, email finance"))
        // One cue + a sequencer the heuristic didn't fully credit.
        XCTAssertTrue(ComplexityClassifier.shouldConsultLLM("summarize this and then relax"))
    }

    // MARK: - parseVerdict

    func testParseVerdict() {
        XCTAssertEqual(ComplexityClassifier.parseVerdict("multi"), true)
        XCTAssertEqual(ComplexityClassifier.parseVerdict("Multi-step"), true)
        XCTAssertEqual(ComplexityClassifier.parseVerdict("single"), false)
        XCTAssertEqual(ComplexityClassifier.parseVerdict("  SINGLE.\n"), false)
        XCTAssertNil(ComplexityClassifier.parseVerdict("I'm not sure"))
        XCTAssertNil(ComplexityClassifier.parseVerdict(""))
    }

    // MARK: - heuristic helpers still behave

    func testHeuristicHelpersExposed() {
        XCTAssertTrue(AgentComplexity.hasSequencer("do x and then y"))
        XCTAssertFalse(AgentComplexity.hasSequencer("just do x"))
        XCTAssertEqual(AgentComplexity.actionCueCount("photo and email and call"), 3)
        // isMultiStep unchanged.
        XCTAssertTrue(AgentComplexity.isMultiStep("take a photo and email it"))
        XCTAssertFalse(AgentComplexity.isMultiStep("what time is it"))
    }
}
