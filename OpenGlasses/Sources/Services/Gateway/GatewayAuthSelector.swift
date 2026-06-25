import Foundation

/// Which credential the connect handshake should present to a gateway.
enum GatewayAuthMode: String, Equatable {
    /// One-time pairing using a setup code's bootstrap token (not yet paired).
    case bootstrap
    /// A previously-issued per-device token (paired).
    case device
    /// A pre-shared gateway token (the legacy/manual path that works today).
    case shared
}

/// Pure precedence for picking the auth mode: a paired device token wins; else a pending setup
/// code triggers bootstrap pairing; else fall back to the shared token (today's behaviour).
/// Heavily tested so the routing can't silently regress.
enum GatewayAuthSelector {
    static func mode(deviceToken: String?, setupCode: String?, sharedToken: String) -> GatewayAuthMode {
        if let deviceToken, !deviceToken.isEmpty { return .device }
        if let setupCode, !setupCode.isEmpty { return .bootstrap }
        return .shared
    }

    static func mode(for gateway: GatewayConfig) -> GatewayAuthMode {
        mode(deviceToken: gateway.deviceToken, setupCode: gateway.setupCode, sharedToken: gateway.token)
    }

    /// The actual token string to put in the handshake for the selected mode (empty if none).
    static func credential(deviceToken: String?, setupCode: String?, sharedToken: String) -> String {
        switch mode(deviceToken: deviceToken, setupCode: setupCode, sharedToken: sharedToken) {
        case .device: return deviceToken ?? ""
        case .bootstrap: return SetupCode.decode(setupCode ?? "")?.bootstrapToken ?? ""
        case .shared: return sharedToken
        }
    }
}
