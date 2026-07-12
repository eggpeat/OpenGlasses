import XCTest
@testable import OpenGlasses

/// BK P4 — local generation must honour barge-in cancellation and run one-at-a-time. The token
/// loop previously polled only background state, so `stop`/barge-in marked the task cancelled but
/// MLX inference ran to completion (GPU/battery burn). Driven through the injected
/// `drainTokenStream` seam (no MLX model / GPU) and the `isGenerating` entry guard.
@MainActor
final class LocalGenerationCancellationTests: XCTestCase {

    // MARK: - drainTokenStream: normal + backgrounding

    func testAccumulatesChunksAndFiresOnToken() async throws {
        var remaining = ["Hello", " ", "world"]
        var tokens: [String] = []
        let out = try await LocalLLMService.drainTokenStream(
            nextChunk: { remaining.isEmpty ? nil : remaining.removeFirst() },
            isBackgrounded: { false },
            onToken: { tokens.append($0) }
        )
        XCTAssertEqual(out, "Hello world")
        XCTAssertEqual(tokens, ["Hello", " ", "world"])
    }

    func testBackgroundingMidStreamReturnsPartial() async throws {
        var count = 0
        let out = try await LocalLLMService.drainTokenStream(
            nextChunk: { count += 1; return "tok\(count)" },
            isBackgrounded: { count >= 2 },   // backgrounds after two tokens flow
            onToken: nil
        )
        XCTAssertEqual(out, "tok1tok2", "returns what was produced before backgrounding")
    }

    func testBackgroundingWithNoOutputThrowsBackgrounded() async {
        do {
            _ = try await LocalLLMService.drainTokenStream(
                nextChunk: { "x" }, isBackgrounded: { true }, onToken: nil)
            XCTFail("expected .backgrounded")
        } catch let error as LocalLLMError {
            guard case .backgrounded = error else { return XCTFail("expected .backgrounded, got \(error)") }
        } catch {
            XCTFail("expected LocalLLMError.backgrounded, got \(error)")
        }
    }

    // MARK: - Barge-in cancellation ALWAYS throws (never a partial return)

    func testCancellationThrowsCancellationErrorNotPartial() async {
        let producing = XCTestExpectation(description: "producing tokens")
        producing.assertForOverFulfill = false
        // An unbounded stream: the ONLY way the task completes is cancellation throwing.
        let task = Task { () -> String in
            try await LocalLLMService.drainTokenStream(
                nextChunk: { await Task.yield(); return "x" },
                isBackgrounded: { false },
                onToken: { _ in producing.fulfill() }
            )
        }
        await fulfillment(of: [producing], timeout: 2.0)

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("barge-in must throw CancellationError, not return a partial reply")
        } catch is CancellationError {
            // Correct — ConversationTurnRunner maps CancellationError → onCancelled, the only path
            // where the partial reply isn't spoken.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testAlreadyCancelledThrowsBeforePullingAnyToken() async {
        var pulled = 0
        let task = Task { () -> String in
            // Cancel the task from within before it starts, so the first checkCancellation fires.
            try await LocalLLMService.drainTokenStream(
                nextChunk: { pulled += 1; return "x" },
                isBackgrounded: { false },
                onToken: nil
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - Entry guard: one generation at a time

    func testConcurrentGenerateThrowsAlreadyGenerating() async {
        let service = LocalLLMService()
        service.isGenerating = true   // a generation is already live
        do {
            _ = try await service.generate(userMessage: "hi", systemPrompt: "sys")
            XCTFail("a second concurrent generate must be refused")
        } catch let error as LocalLLMError {
            guard case .alreadyGenerating = error else {
                return XCTFail("expected .alreadyGenerating, got \(error)")
            }
        } catch {
            XCTFail("expected LocalLLMError.alreadyGenerating, got \(error)")
        }
    }
}
