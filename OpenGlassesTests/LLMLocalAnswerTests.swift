import XCTest
@testable import OpenGlasses

/// BK P3 — the local path must not produce silent dead air. A completion that strips to empty (all
/// `<tool_call>` markup, or an immediate EOS) is rejected as an error rather than handed to TTS as
/// an empty string (which it drops silently). Both `sendLocal` return paths — the tool-call
/// `cleanFinal` and the no-tool `finalAnswer` — run through this one validator, matching the
/// Anthropic/Gemini empty-completion guards.
final class LLMLocalAnswerTests: XCTestCase {

    func testKeepsRealTextTrimmed() throws {
        XCTAssertEqual(try LLMService.cleanedNonEmptyLocalAnswer("Hello there"), "Hello there")
        XCTAssertEqual(try LLMService.cleanedNonEmptyLocalAnswer("  padded  "), "padded")
    }

    func testStripsToolCallButKeepsSurroundingText() throws {
        XCTAssertEqual(
            try LLMService.cleanedNonEmptyLocalAnswer(#"The answer is 42 <tool_call>{"name":"x","arguments":{}}</tool_call>"#),
            "The answer is 42")
    }

    func testEmptyOrWhitespaceThrowsInvalidResponseLocal() {
        for raw in ["", "   ", "\n\t "] {
            XCTAssertThrowsError(try LLMService.cleanedNonEmptyLocalAnswer(raw)) { error in
                guard case LLMError.invalidResponse(let who) = error else {
                    return XCTFail("expected invalidResponse, got \(error)")
                }
                XCTAssertEqual(who, "Local")
            }
        }
    }

    func testToolCallOnlyOutputThrows() {
        // A model that answers with nothing but tool-call markup → stripped to empty → error,
        // not an empty string forwarded to the speaker (the whole point of BK P3).
        XCTAssertThrowsError(
            try LLMService.cleanedNonEmptyLocalAnswer(#"<tool_call>{"name":"weather","arguments":{}}</tool_call>"#)
        ) { error in
            guard case LLMError.invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        }
        // Whitespace padding around the markup is still empty after cleaning.
        XCTAssertThrowsError(try LLMService.cleanedNonEmptyLocalAnswer("  <tool_call>{}</tool_call>  \n"))
    }
}
