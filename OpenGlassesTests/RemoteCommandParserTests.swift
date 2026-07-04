import XCTest
@testable import OpenGlasses

/// Plan BH — the pure parser for inbound gateway request frames. Total by construction: every
/// request frame yields a command, a typed `.unsupported`, or a typed `.malformed`.
final class RemoteCommandParserTests: XCTestCase {

    private func frame(method: String = "node.invoke", id: Any? = "req-1", params: [String: Any]?) -> [String: Any] {
        var f: [String: Any] = ["type": "req", "method": method]
        if let id { f["id"] = id }
        if let params { f["params"] = params }
        return f
    }

    // MARK: - Frame recognition

    func testNonRequestFramesAreNotParsed() {
        XCTAssertNil(RemoteCommandParser.parse(["type": "event", "event": "heartbeat"]))
        XCTAssertNil(RemoteCommandParser.parse(["type": "res", "id": "x"]))
        XCTAssertNil(RemoteCommandParser.parse(["method": "node.invoke"]))   // no type
        XCTAssertNil(RemoteCommandParser.parse(["type": "req"]))             // no method
    }

    func testUnknownMethodIsUnsupportedNotSilent() {
        let request = RemoteCommandParser.parse(frame(method: "node.ping", params: nil))
        XCTAssertEqual(request?.outcome, .unsupported(action: "node.ping"))
        XCTAssertEqual(request?.id, "req-1")
    }

    func testNumericIdIsStringified() {
        let request = RemoteCommandParser.parse(frame(id: 42, params: ["action": "status"]))
        XCTAssertEqual(request?.id, "42")
    }

    func testMissingIdYieldsEmptyIdNotNil() {
        let request = RemoteCommandParser.parse(frame(id: nil, params: ["action": "status"]))
        XCTAssertEqual(request?.id, "")
        XCTAssertEqual(request?.outcome, .command(.deviceStatus))
    }

    // MARK: - Actions

    func testMissingActionIsMalformed() {
        let request = RemoteCommandParser.parse(frame(params: [:]))
        XCTAssertEqual(request?.outcome, .malformed(reason: "missing params.action"))
    }

    func testUnknownActionIsUnsupportedWithOriginalSpelling() {
        let request = RemoteCommandParser.parse(frame(params: ["action": "Launch_Missiles"]))
        XCTAssertEqual(request?.outcome, .unsupported(action: "Launch_Missiles"))
    }

    func testActionMatchingIsCaseAndWhitespaceInsensitive() {
        let request = RemoteCommandParser.parse(frame(params: ["action": "  Capture_Photo "]))
        XCTAssertEqual(request?.outcome, .command(.capturePhoto))
    }

    func testActionAliasKeysCommandAndName() {
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["command": "status"]))?.outcome,
                       .command(.deviceStatus))
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["name": "stop_all"]))?.outcome,
                       .command(.stopAll))
    }

    func testEveryKnownAliasParsesToACommand() {
        for alias in RemoteCommandParser.knownAliases {
            // Provide the superset of params so text-requiring commands parse too.
            let params: [String: Any] = ["action": alias, "text": "hello", "source": "de", "target": "en"]
            let request = RemoteCommandParser.parse(frame(params: params))
            guard case .command = request?.outcome else {
                return XCTFail("alias '\(alias)' did not parse to a command: \(String(describing: request?.outcome))")
            }
        }
    }

    // MARK: - Param validation

    func testSpeakRequiresText() {
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["action": "speak"]))?.outcome,
                       .malformed(reason: "speak requires text"))
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["action": "speak", "text": ""]))?.outcome,
                       .malformed(reason: "speak requires text"))
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["action": "say", "message": "hi"]))?.outcome,
                       .command(.speak(text: "hi")))
    }

    func testDisplayShowRequiresTextAndCarriesIcon() {
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["action": "show_text"]))?.outcome,
                       .malformed(reason: "display_show requires text"))
        XCTAssertEqual(
            RemoteCommandParser.parse(frame(params: ["action": "display_show", "text": "On my way", "icon": "info"]))?.outcome,
            .command(.displayShow(text: "On my way", icon: "info"))
        )
    }

    func testTranslationCarriesOptionalLanguages() {
        XCTAssertEqual(
            RemoteCommandParser.parse(frame(params: ["action": "start_translation", "from": "de", "to": "en"]))?.outcome,
            .command(.startTranslation(source: "de", target: "en"))
        )
        XCTAssertEqual(
            RemoteCommandParser.parse(frame(params: ["action": "start_translation"]))?.outcome,
            .command(.startTranslation(source: nil, target: nil))
        )
    }

    func testAddNoteRequiresText() {
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["action": "add_note"]))?.outcome,
                       .malformed(reason: "add_note requires text"))
        XCTAssertEqual(RemoteCommandParser.parse(frame(params: ["action": "note", "content": "milk"]))?.outcome,
                       .command(.addNote(text: "milk")))
    }

    // MARK: - Class assignments (the consent surface)

    func testCaptureClassCoversEverySensorStart() {
        let sensorStarts: [RemoteGlassesCommand] = [
            .capturePhoto, .startAudioRecording, .startVideo,
            .startTranslation(source: nil, target: nil), .startTranscription,
        ]
        for command in sensorStarts {
            XCTAssertEqual(command.commandClass, .capture, "\(command) must be consent-gated as capture")
        }
    }

    func testStopsAreHaltClassSoARemoteAgentCanAlwaysReduceActivity() {
        let stops: [RemoteGlassesCommand] = [
            .stopAudioRecording, .stopVideo, .stopTranslation, .stopTranscription, .stopAll,
        ]
        for command in stops {
            XCTAssertEqual(command.commandClass, .halt)
        }
    }
}
