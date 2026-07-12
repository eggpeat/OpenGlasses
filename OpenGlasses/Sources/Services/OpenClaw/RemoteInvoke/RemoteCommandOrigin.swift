import Foundation

/// Who issued a remote-invoke command (Plan BN P2). The remote-invoke policy plane was
/// caller-blind: one shared rate-bucket set and un-attributed audit entries, so a chatty MCP peer
/// could starve the gateway's budget and BL P4's "every call attributed to the peer's API key" had
/// no seam. Origin threads a caller identity through `decide()`, the rate state (per-origin
/// buckets), and the audit trail.
///
/// One identity story, two transports (plan point 4): the outbound gateway socket authenticates
/// with the Plan AR `deviceId`/Ed25519 pair; an inbound MCP peer is identified by its API key
/// (BL P4). Both land here as an `origin` — no second mechanism.
enum RemoteCommandOrigin: Hashable, Codable {
    case gateway                 // the OpenClaw gateway socket (Plan BH — the only caller today)
    case mcpPeer(id: String)     // an MCP peer driving the glasses, keyed by its API-key id (BL P4)

    /// Stable label for the audit trail + rate-bucket key: "gateway" / "peer:<id>".
    var label: String {
        switch self {
        case .gateway:          return "gateway"
        case .mcpPeer(let id):  return "peer:\(id)"
        }
    }

    /// Human-facing name for the activity log and the shared consent surface.
    var displayName: String {
        switch self {
        case .gateway:          return "Gateway"
        case .mcpPeer(let id):  return id.isEmpty ? "MCP peer" : "Peer \(id)"
        }
    }

    /// Bridge to the shared consent surface (Plan BN P1): an MCP-peer origin asks as an ops peer,
    /// the gateway as the gateway — so BL P4's capture consent is attributed without a second map.
    var consentSource: RemoteActionSource {
        switch self {
        case .gateway:          return .gateway
        case .mcpPeer(let id):  return .opsPeer(label: displayName)
        }
    }
}
