import Foundation

// MARK: - Gateway Configuration

/// Known gateway providers — users can also add custom ones.
enum GatewayProvider: String, Codable, CaseIterable, Identifiable {
    case openclaw = "openclaw"
    case nanoclaw = "nanoclaw"
    case nemoclaw = "nemoclaw"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openclaw: return "OpenClaw"
        case .nanoclaw: return "NanoClaw"
        case .nemoclaw: return "NemoClaw"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .openclaw: return "server.rack"
        case .nanoclaw: return "desktopcomputer"
        case .nemoclaw: return "cpu"
        case .custom: return "gear"
        }
    }

    var defaultPort: Int {
        switch self {
        case .openclaw: return 18789
        case .nanoclaw: return 18789
        case .nemoclaw: return 18789
        case .custom: return 18789
        }
    }

    /// Whether this provider uses the standard OpenClaw WebSocket protocol.
    var usesOpenClawProtocol: Bool { true }
}

/// A configured gateway endpoint — could be OpenClaw, NanoClaw, NemoClaw, or custom.
struct GatewayConfig: Codable, Identifiable, Equatable {
    var id: String
    var name: String                    // User label, e.g. "Mac Mini OpenClaw"
    var provider: String                // GatewayProvider rawValue
    var lanHost: String                 // LAN/local IP or hostname
    var port: Int                       // Default 18789
    var tunnelHost: String              // Tailscale or tunnel URL
    var token: String                   // Pre-shared gateway auth token (legacy/manual path)
    var connectionMode: String          // "auto", "lan", "tunnel"
    var enabled: Bool
    var priority: Int                   // Lower = tried first
    // Device pairing (optional w/ nil default → backward-compatible with previously-saved
    // gateways and with every existing memberwise-init call site):
    var deviceToken: String? = nil      // Per-device token issued by the gateway after approval
    var deviceId: String? = nil         // Stable per-device identity sent in the handshake
    var setupCode: String? = nil        // Transient bootstrap code, cleared once a device token lands

    var gatewayProvider: GatewayProvider {
        GatewayProvider(rawValue: provider) ?? .custom
    }

    var connectionModeEnum: OpenClawConnectionMode {
        OpenClawConnectionMode(rawValue: connectionMode) ?? .auto
    }

    /// Build the LAN URL from host + port.
    var lanURL: String {
        let host = lanHost.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty else { return "" }
        return "\(host):\(port)"
    }

    /// The tunnel URL (already includes port usually).
    var tunnelURL: String {
        tunnelHost.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// True when there's a usable credential (shared token *or* a paired device token) and a
    /// host to reach. A device-paired gateway needs no shared token.
    var isConfigured: Bool {
        let hasCredential = !token.isEmpty || !(deviceToken ?? "").isEmpty
        return hasCredential && (!lanHost.isEmpty || !tunnelHost.isEmpty)
    }

    /// Create a new gateway with defaults for a given provider.
    static func newGateway(provider: GatewayProvider, priority: Int = 0) -> GatewayConfig {
        GatewayConfig(
            id: UUID().uuidString,
            name: "\(provider.displayName) Gateway",
            provider: provider.rawValue,
            lanHost: "",
            port: provider.defaultPort,
            tunnelHost: "",
            token: "",
            connectionMode: "auto",
            enabled: true,
            priority: priority
        )
    }
}
