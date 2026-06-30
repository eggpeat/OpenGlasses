import XCTest
@testable import OpenGlasses

final class RealtimeUsageTests: XCTestCase {

    // MARK: - OpenAI Realtime (per-response)

    func testOpenAIResponseUsage() {
        let event: [String: Any] = [
            "type": "response.done",
            "response": ["usage": ["input_tokens": 120, "output_tokens": 45, "total_tokens": 165]]
        ]
        let u = RealtimeUsage.openAIResponseUsage(event)
        XCTAssertEqual(u?.tokensIn, 120)
        XCTAssertEqual(u?.tokensOut, 45)
    }

    func testOpenAINoUsageBlock() {
        XCTAssertNil(RealtimeUsage.openAIResponseUsage(["type": "response.done", "response": [:]]))
        XCTAssertNil(RealtimeUsage.openAIResponseUsage(["type": "response.done"]))
    }

    // MARK: - Gemini Live (cumulative)

    func testGeminiCumulativePrefersResponseTokenCount() {
        let msg: [String: Any] = ["usageMetadata": ["promptTokenCount": 30, "responseTokenCount": 12, "candidatesTokenCount": 99]]
        let u = RealtimeUsage.geminiCumulative(msg)
        XCTAssertEqual(u?.tokensIn, 30)
        XCTAssertEqual(u?.tokensOut, 12)   // responseTokenCount wins
    }

    func testGeminiCumulativeFallsBackToCandidates() {
        let msg: [String: Any] = ["usageMetadata": ["promptTokenCount": 30, "candidatesTokenCount": 8]]
        XCTAssertEqual(RealtimeUsage.geminiCumulative(msg)?.tokensOut, 8)
    }

    func testGeminiNoUsageMetadata() {
        XCTAssertNil(RealtimeUsage.geminiCumulative(["serverContent": [:]]))
    }

    // MARK: - CumulativeUsageMeter

    func testMeterReturnsDeltas() {
        var meter = CumulativeUsageMeter()
        XCTAssertEqual(meter.delta(tokensIn: 30, tokensOut: 10).tokensIn, 30)
        // Second cumulative reading → only the new tokens.
        let d2 = meter.delta(tokensIn: 50, tokensOut: 25)
        XCTAssertEqual(d2.tokensIn, 20)
        XCTAssertEqual(d2.tokensOut, 15)
        // No change → zero delta.
        let d3 = meter.delta(tokensIn: 50, tokensOut: 25)
        XCTAssertEqual(d3.tokensIn, 0)
        XCTAssertEqual(d3.tokensOut, 0)
    }

    func testMeterNeverNegativeOnReset() {
        var meter = CumulativeUsageMeter()
        _ = meter.delta(tokensIn: 100, tokensOut: 40)
        // A lower reading (session reset) yields 0, not a negative.
        let d = meter.delta(tokensIn: 5, tokensOut: 2)
        XCTAssertEqual(d.tokensIn, 0)
        XCTAssertEqual(d.tokensOut, 0)
        // And subsequent growth resumes from the higher baseline.
        let d2 = meter.delta(tokensIn: 110, tokensOut: 45)
        XCTAssertEqual(d2.tokensIn, 10)
        XCTAssertEqual(d2.tokensOut, 5)
    }
}
