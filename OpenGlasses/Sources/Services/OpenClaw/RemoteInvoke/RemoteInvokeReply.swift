import Foundation

/// Pure reply-envelope builder for remote invoke (Plan BH). Every inbound request frame yields
/// exactly one well-formed response frame — success, deny, unsupported, malformed, or error —
/// always carrying the request `id` so the gateway can correlate.
enum RemoteInvokeReply {

    static func success(id: String, payload: [String: Any] = [:]) -> [String: Any] {
        var reply = base(id: id, ok: true)
        if !payload.isEmpty { reply["payload"] = payload }
        return reply
    }

    static func denied(id: String, reason: RemoteCommandPolicy.DenyReason) -> [String: Any] {
        error(id: id, code: reason.code, message: reason.message)
    }

    static func unsupported(id: String, action: String) -> [String: Any] {
        error(id: id, code: "unsupported_action", message: "Unsupported action: \(action)")
    }

    static func malformed(id: String, reason: String) -> [String: Any] {
        error(id: id, code: "malformed_request", message: reason)
    }

    static func failure(id: String, message: String) -> [String: Any] {
        error(id: id, code: "execution_failed", message: message)
    }

    // MARK: - Private

    private static func base(id: String, ok: Bool) -> [String: Any] {
        ["type": "res", "id": id, "ok": ok]
    }

    private static func error(id: String, code: String, message: String) -> [String: Any] {
        var reply = base(id: id, ok: false)
        reply["error"] = ["code": code, "message": message]
        return reply
    }
}
