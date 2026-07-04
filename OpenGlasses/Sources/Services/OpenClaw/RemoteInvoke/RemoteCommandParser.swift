import Foundation

/// Pure parser for inbound gateway request frames (Plan BH). JSON-RPC-ish frame
/// (`type:"req"`, `method`, `id`, `params`) → typed `RemoteGlassesCommand`.
///
/// Total by construction: every request frame yields exactly one outcome — a command, a typed
/// `.unsupported`, or a typed `.malformed` — never a crash, never silence. The alias table is
/// data-driven so multiple verbs (and later locale aliases) map onto one canonical command.
enum RemoteCommandParser {

    /// A parsed inbound request: the reply correlation `id` plus what the frame asked for.
    struct Request: Equatable {
        let id: String
        let outcome: Outcome
    }

    enum Outcome: Equatable {
        case command(RemoteGlassesCommand)
        case unsupported(action: String)
        case malformed(reason: String)
    }

    /// Methods that carry a device-action invoke. The action verb itself travels in
    /// `params.action` (aliases: `command`, `name`).
    static let invokeMethods: Set<String> = ["node.invoke", "device.invoke", "invoke"]

    /// True when a decoded frame is a server→client request we should answer.
    static func isRequestFrame(_ json: [String: Any]) -> Bool {
        (json["type"] as? String) == "req" && json["method"] is String
    }

    /// Parse a request frame. Returns `nil` only when the frame is not a request at all
    /// (wrong/missing `type` or `method`); everything else produces a replyable `Request`.
    static func parse(_ json: [String: Any]) -> Request? {
        guard isRequestFrame(json), let method = json["method"] as? String else { return nil }
        let id = (json["id"] as? String) ?? (json["id"] as? Int).map(String.init) ?? ""
        let params = json["params"] as? [String: Any] ?? [:]

        guard invokeMethods.contains(method) else {
            return Request(id: id, outcome: .unsupported(action: method))
        }
        guard let rawAction = firstString(in: params, keys: ["action", "command", "name"]) else {
            return Request(id: id, outcome: .malformed(reason: "missing params.action"))
        }
        let action = rawAction.lowercased().trimmingCharacters(in: .whitespaces)
        guard let build = builders[action] else {
            return Request(id: id, outcome: .unsupported(action: rawAction))
        }
        return Request(id: id, outcome: build(params))
    }

    // MARK: - Alias table

    private typealias Builder = ([String: Any]) -> Outcome

    /// Wire alias → command builder. Builders validate their own params so a recognized verb
    /// with unusable arguments is `.malformed`, not `.unsupported`.
    private static let builders: [String: Builder] = {
        var t: [String: Builder] = [:]
        func alias(_ names: [String], _ builder: @escaping Builder) {
            for n in names { t[n] = builder }
        }

        alias(["capture_photo", "take_photo", "take_picture", "photo"]) { _ in .command(.capturePhoto) }
        alias(["start_audio_recording", "record_audio", "start_audio"]) { _ in .command(.startAudioRecording) }
        alias(["stop_audio_recording", "stop_audio"]) { _ in .command(.stopAudioRecording) }
        alias(["start_video", "start_video_recording", "record_video"]) { _ in .command(.startVideo) }
        alias(["stop_video", "stop_video_recording"]) { _ in .command(.stopVideo) }
        alias(["start_translation", "translate_live"]) { params in
            .command(.startTranslation(
                source: firstString(in: params, keys: ["source", "from"]),
                target: firstString(in: params, keys: ["target", "to"])
            ))
        }
        alias(["stop_translation"]) { _ in .command(.stopTranslation) }
        alias(["start_transcription", "start_captions", "transcribe"]) { _ in .command(.startTranscription) }
        alias(["stop_transcription", "stop_captions"]) { _ in .command(.stopTranscription) }
        alias(["speak", "say", "tts"]) { params in
            guard let text = firstString(in: params, keys: ["text", "message", "say"]), !text.isEmpty else {
                return .malformed(reason: "speak requires text")
            }
            return .command(.speak(text: text))
        }
        alias(["display_show", "show_text", "display_text", "hud_show"]) { params in
            guard let text = firstString(in: params, keys: ["text", "message", "body"]), !text.isEmpty else {
                return .malformed(reason: "display_show requires text")
            }
            return .command(.displayShow(text: text, icon: firstString(in: params, keys: ["icon"])))
        }
        alias(["display_clear", "clear_display", "hud_clear"]) { _ in .command(.displayClear) }
        alias(["device_status", "status"]) { _ in .command(.deviceStatus) }
        alias(["device_capabilities", "capabilities"]) { _ in .command(.deviceCapabilities) }
        alias(["add_note", "save_note", "note"]) { params in
            guard let text = firstString(in: params, keys: ["text", "content", "note"]), !text.isEmpty else {
                return .malformed(reason: "add_note requires text")
            }
            return .command(.addNote(text: text))
        }
        alias(["get_transcript", "read_transcript", "transcript"]) { _ in .command(.getTranscript) }
        alias(["stop_all", "cancel_all", "stop_everything"]) { _ in .command(.stopAll) }
        return t
    }()

    /// All recognized wire aliases — exposed for tests (every alias must parse, no dead rows).
    static var knownAliases: [String] { Array(builders.keys) }

    private static func firstString(in params: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = params[key] as? String { return value }
        }
        return nil
    }
}
