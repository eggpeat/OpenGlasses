import Foundation

/// Live pairing/connection state, surfaced to the gateway settings UI.
enum PairingStatus: Equatable {
    case disconnected
    case connecting
    /// Bootstrap accepted; the device is awaiting approval on the gateway.
    case waitingApproval
    /// Connected and authenticated (newly paired, or an already-valid token).
    case paired
    case error(String)
}

/// The result of interpreting a gateway message: the new status, plus any device token the
/// gateway issued (which the caller persists).
struct PairingOutcome: Equatable {
    let status: PairingStatus
    let deviceToken: String?
}

/// Pure mapping from a gateway `res`/`event` JSON to a `PairingOutcome`. No I/O — exhaustively
/// tested against the success, pending-approval, and failure shapes.
enum PairingResponseInterpreter {

    /// Interpret a `res` response to the connect handshake.
    static func interpretResponse(_ json: [String: Any]) -> PairingOutcome {
        let ok = json["ok"] as? Bool ?? false

        if ok {
            // A device token in the result means pairing just completed.
            if let result = json["result"] as? [String: Any],
               let token = (result["token"] as? String), !token.isEmpty {
                return PairingOutcome(status: .paired, deviceToken: token)
            }
            // Otherwise it's an ordinary authenticated connect (shared token / already paired).
            return PairingOutcome(status: .paired, deviceToken: nil)
        }

        let error = json["error"] as? [String: Any]
        let message = (error?["message"] as? String) ?? "Connection failed"
        if isPendingApproval(code: error?["code"], message: message) {
            return PairingOutcome(status: .waitingApproval, deviceToken: nil)
        }
        return PairingOutcome(status: .error(message), deviceToken: nil)
    }

    /// Interpret a `device.paired` event payload (the gateway approved out-of-band).
    static func interpretPairedEvent(_ payload: [String: Any]) -> PairingOutcome? {
        guard let token = payload["token"] as? String, !token.isEmpty else { return nil }
        return PairingOutcome(status: .paired, deviceToken: token)
    }

    /// True when an error means "waiting for the user to approve this device on the gateway".
    /// Tolerates the code being a string (`"pairing_pending"`) or the message mentioning it.
    static func isPendingApproval(code: Any?, message: String) -> Bool {
        if let codeString = code as? String,
           codeString == "pairing_pending" || codeString == "pairing_required" {
            return true
        }
        let lower = message.lowercased()
        return lower.contains("pairing") || lower.contains("approval") || lower.contains("approve")
    }
}
