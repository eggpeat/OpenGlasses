import XCTest
@testable import OpenGlasses

/// Plan BG P2 — the pure routing core of the conversation flow: an ordered `VoiceCommandHandler`
/// chain where the first handler to consume the transcript wins and short-circuits the rest.
final class ConversationFlowEngineTests: XCTestCase {

    /// Records which handlers ran, in order, so we can assert short-circuiting.
    private func recordingHandler(_ label: String, consumes: Bool, into log: Box<[String]>) -> VoiceCommandHandler {
        VoiceCommandHandler(label: label) { _ in
            log.value.append(label)
            return consumes
        }
    }

    func testFirstConsumingHandlerWinsAndShortCircuits() async {
        let ran = Box<[String]>([])
        let engine = ConversationFlowEngine(handlers: [
            recordingHandler("a", consumes: false, into: ran),
            recordingHandler("b", consumes: true, into: ran),
            recordingHandler("c", consumes: true, into: ran),   // must never run
        ])
        let consumed = await engine.route("hello")
        XCTAssertEqual(consumed, "b")
        XCTAssertEqual(ran.value, ["a", "b"], "handlers run in order; nothing after the winner runs")
    }

    func testNoHandlerConsumesReturnsNil() async {
        let ran = Box<[String]>([])
        let engine = ConversationFlowEngine(handlers: [
            recordingHandler("a", consumes: false, into: ran),
            recordingHandler("b", consumes: false, into: ran),
        ])
        let consumed = await engine.route("weather?")
        XCTAssertNil(consumed, "nothing consumed → caller proceeds to the LLM")
        XCTAssertEqual(ran.value, ["a", "b"], "every handler is offered the transcript")
    }

    func testEmptyChainReturnsNil() async {
        let consumed = await ConversationFlowEngine(handlers: []).route("anything")
        XCTAssertNil(consumed)
    }

    func testFirstHandlerCanWinImmediately() async {
        let ran = Box<[String]>([])
        let engine = ConversationFlowEngine(handlers: [
            recordingHandler("first", consumes: true, into: ran),
            recordingHandler("second", consumes: true, into: ran),
        ])
        let consumed = await engine.route("next")
        XCTAssertEqual(consumed, "first")
        XCTAssertEqual(ran.value, ["first"], "the rest of the chain is skipped")
    }

    func testHandlerReceivesTheTranscript() async {
        var seen: String?
        let engine = ConversationFlowEngine(handlers: [
            VoiceCommandHandler(label: "capture") { text in seen = text; return true }
        ])
        _ = await engine.route("open the menu")
        XCTAssertEqual(seen, "open the menu")
    }
}
