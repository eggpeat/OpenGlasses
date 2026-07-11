import XCTest
@testable import OpenGlasses

final class StreamingUsageAccumulatorTests: XCTestCase {

    // MARK: - Anthropic

    func testAnthropicSplitAcrossStartAndDeltas() {
        var acc = StreamingUsageAccumulator()
        acc.consumeAnthropic(["type": "message_start",
                              "message": ["usage": ["input_tokens": 42, "output_tokens": 1]]])
        acc.consumeAnthropic(["type": "content_block_delta", "delta": ["type": "text_delta", "text": "hi"]])
        acc.consumeAnthropic(["type": "message_delta", "usage": ["output_tokens": 7]])
        acc.consumeAnthropic(["type": "message_delta", "usage": ["output_tokens": 15]])  // cumulative
        XCTAssertEqual(acc.tokensIn, 42)
        XCTAssertEqual(acc.tokensOut, 15)
        XCTAssertTrue(acc.hasUsage)
    }

    func testAnthropicCumulativeOutputNeverDecreases() {
        var acc = StreamingUsageAccumulator()
        acc.consumeAnthropic(["type": "message_delta", "usage": ["output_tokens": 20]])
        acc.consumeAnthropic(["type": "message_delta", "usage": ["output_tokens": 18]])  // stale/lower
        XCTAssertEqual(acc.tokensOut, 20)
    }

    func testAnthropicCacheTokensCapturedFromMessageStart() {
        var acc = StreamingUsageAccumulator()
        acc.consumeAnthropic(["type": "message_start",
                              "message": ["usage": ["input_tokens": 42, "output_tokens": 1,
                                                    "cache_creation_input_tokens": 100,
                                                    "cache_read_input_tokens": 200]]])
        XCTAssertEqual(acc.cacheWriteTokens, 100)
        XCTAssertEqual(acc.cacheReadTokens, 200)
        XCTAssertTrue(acc.hasUsage)
    }

    func testAnthropicNoUsageEvents() {
        var acc = StreamingUsageAccumulator()
        acc.consumeAnthropic(["type": "content_block_start", "index": 0])
        acc.consumeAnthropic(["type": "content_block_delta", "delta": ["type": "text_delta", "text": "x"]])
        XCTAssertFalse(acc.hasUsage)
        XCTAssertEqual(acc.tokensIn, 0)
        XCTAssertEqual(acc.tokensOut, 0)
    }

    // MARK: - OpenAI

    func testOpenAIFinalChunkUsage() {
        var acc = StreamingUsageAccumulator()
        // content chunks carry no usage…
        acc.consumeOpenAI(["choices": [["delta": ["content": "hello"]]]])
        // …the final include_usage chunk does (empty choices).
        acc.consumeOpenAI(["choices": [], "usage": ["prompt_tokens": 12, "completion_tokens": 8]])
        XCTAssertEqual(acc.tokensIn, 12)
        XCTAssertEqual(acc.tokensOut, 8)
    }

    func testOpenAICachedReadFromPromptTokenDetails() {
        var acc = StreamingUsageAccumulator()
        acc.consumeOpenAI(["choices": [], "usage": ["prompt_tokens": 12, "completion_tokens": 8,
                                                    "prompt_tokens_details": ["cached_tokens": 4]]])
        XCTAssertEqual(acc.cacheReadTokens, 4)
    }

    func testOpenAINoUsageWhenServerOmitsIt() {
        var acc = StreamingUsageAccumulator()
        acc.consumeOpenAI(["choices": [["delta": ["content": "hi"]]]])
        XCTAssertFalse(acc.hasUsage)
    }

    func testCoercesNumericTypes() {
        var acc = StreamingUsageAccumulator()
        acc.consumeOpenAI(["usage": ["prompt_tokens": Double(10), "completion_tokens": NSNumber(value: 5)]])
        XCTAssertEqual(acc.tokensIn, 10)
        XCTAssertEqual(acc.tokensOut, 5)
    }
}
