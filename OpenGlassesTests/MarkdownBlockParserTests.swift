import XCTest
@testable import OpenGlasses

/// Tests for the pure chat-message segmenter that splits prose from fenced code blocks.
final class MarkdownBlockParserTests: XCTestCase {

    func testEmptyAndWhitespaceProduceNoBlocks() {
        XCTAssertEqual(MarkdownBlockParser.parse(""), [])
        XCTAssertEqual(MarkdownBlockParser.parse("   \n\n  \t"), [])
    }

    func testPlainProse() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("Hello there.\nHow are you?"),
            [.prose("Hello there.\nHow are you?")]
        )
    }

    func testSingleCodeBlockWithLanguageSurroundedByProse() {
        let input = """
        Here is some Swift:
        ```swift
        let x = 1
        print(x)
        ```
        That's it.
        """
        XCTAssertEqual(MarkdownBlockParser.parse(input), [
            .prose("Here is some Swift:"),
            .code(language: "swift", body: "let x = 1\nprint(x)"),
            .prose("That's it.")
        ])
    }

    func testCodeBlockWithoutLanguage() {
        let input = """
        ```
        plain code
        ```
        """
        XCTAssertEqual(MarkdownBlockParser.parse(input), [
            .code(language: nil, body: "plain code")
        ])
    }

    func testUnterminatedFenceCapturesRemainderAsCode() {
        let input = """
        intro
        ```python
        x = 1
        y = 2
        """
        XCTAssertEqual(MarkdownBlockParser.parse(input), [
            .prose("intro"),
            .code(language: "python", body: "x = 1\ny = 2")
        ])
    }

    func testCodePreservesIndentationAndBlankLines() {
        let input = """
        ```
        def f():

            return 1
        ```
        """
        XCTAssertEqual(MarkdownBlockParser.parse(input), [
            .code(language: nil, body: "def f():\n\n    return 1")
        ])
    }

    func testMultipleCodeBlocks() {
        let input = """
        a
        ```
        one
        ```
        b
        ```
        two
        ```
        """
        XCTAssertEqual(MarkdownBlockParser.parse(input), [
            .prose("a"),
            .code(language: nil, body: "one"),
            .prose("b"),
            .code(language: nil, body: "two")
        ])
    }

    func testCarriageReturnsAreNormalized() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("line1\r\nline2"),
            [.prose("line1\nline2")]
        )
    }
}
