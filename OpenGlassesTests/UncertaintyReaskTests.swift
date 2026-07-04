import XCTest
@testable import OpenGlasses

/// Plan BI — one bounded, transparent, never-worse-than-today web-grounded re-ask.
final class UncertaintyReaskTests: XCTestCase {

    private struct TestError: Error {}

    func testHappyPathGroundsRegeneratesOnceAndPrefixes() async {
        let regenerateCalls = Box<[String]>([])
        let result = await UncertaintyReask.answer(
            question: "What's the latest Swift version?",
            originalAnswer: "I think it's 5.9 but I'm not sure.",
            search: { query in
                XCTAssertEqual(query, "What's the latest Swift version?")
                return "Swift 6.2 was released in June 2026."
            },
            regenerate: { grounding in
                regenerateCalls.value.append(grounding)
                return "The latest Swift version is 6.2."
            }
        )
        XCTAssertEqual(result, UncertaintyReask.transparencyPrefix + "The latest Swift version is 6.2.",
                       "the re-grounded answer must carry the transparency prefix — never a silent swap")
        XCTAssertEqual(regenerateCalls.value.count, 1, "exactly one regeneration — no loops")
        XCTAssertTrue(regenerateCalls.value[0].contains("Swift 6.2 was released"),
                      "search results are spliced into the grounding prompt")
        XCTAssertTrue(regenerateCalls.value[0].contains("What's the latest Swift version?"),
                      "the original question is restated in the grounding prompt")
    }

    func testEmptySearchReturnsOriginalWithoutRegenerating() async {
        let regenerated = Box<[String]>([])
        let result = await UncertaintyReask.answer(
            question: "q", originalAnswer: "original",
            search: { _ in "   \n " },
            regenerate: { g in regenerated.value.append(g); return "should not happen" }
        )
        XCTAssertEqual(result, "original")
        XCTAssertTrue(regenerated.value.isEmpty)
    }

    func testNilSearchReturnsOriginal() async {
        let result = await UncertaintyReask.answer(
            question: "q", originalAnswer: "original",
            search: { _ in nil },
            regenerate: { _ in "should not happen" }
        )
        XCTAssertEqual(result, "original")
    }

    func testSearchThrowReturnsOriginal() async {
        let result = await UncertaintyReask.answer(
            question: "q", originalAnswer: "original",
            search: { _ in throw TestError() },
            regenerate: { _ in "should not happen" }
        )
        XCTAssertEqual(result, "original", "a failed search must never make the answer worse")
    }

    func testRegenerateThrowReturnsOriginal() async {
        let result = await UncertaintyReask.answer(
            question: "q", originalAnswer: "original",
            search: { _ in "some results" },
            regenerate: { _ in throw TestError() }
        )
        XCTAssertEqual(result, "original")
    }

    func testEmptyRegenerationReturnsOriginal() async {
        let result = await UncertaintyReask.answer(
            question: "q", originalAnswer: "original",
            search: { _ in "some results" },
            regenerate: { _ in "  \n" }
        )
        XCTAssertEqual(result, "original")
    }
}
