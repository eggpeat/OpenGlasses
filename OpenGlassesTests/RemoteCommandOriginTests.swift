import XCTest
@testable import OpenGlasses

/// Plan BN P2 — origin-aware remote-command policy: per-origin rate buckets (a chatty peer can't
/// starve the gateway), origin-attributed audit entries, and the consent-surface bridge. The
/// gateway-origin behaviour is byte-identical, guarded by the unchanged `RemoteCommandPolicyTests`.
final class RemoteCommandOriginTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Origin identity

    func testOriginLabelsDisplayAndConsentBridge() {
        XCTAssertEqual(RemoteCommandOrigin.gateway.label, "gateway")
        XCTAssertEqual(RemoteCommandOrigin.mcpPeer(id: "acme").label, "peer:acme")
        XCTAssertEqual(RemoteCommandOrigin.gateway.displayName, "Gateway")
        XCTAssertEqual(RemoteCommandOrigin.mcpPeer(id: "acme").displayName, "Peer acme")
        XCTAssertEqual(RemoteCommandOrigin.mcpPeer(id: "").displayName, "MCP peer")
        // Bridges to the shared consent surface (BN P1): gateway → .gateway, peer → .opsPeer.
        XCTAssertEqual(RemoteCommandOrigin.gateway.consentSource, .gateway)
        XCTAssertEqual(RemoteCommandOrigin.mcpPeer(id: "acme").consentSource, .opsPeer(label: "Peer acme"))
        // Distinct peers are distinct dictionary keys.
        XCTAssertNotEqual(RemoteCommandOrigin.mcpPeer(id: "a"), RemoteCommandOrigin.mcpPeer(id: "b"))
    }

    // MARK: - Per-origin rate isolation (pure state)

    func testOriginsHaveIndependentRateBuckets() {
        var rate = RemoteInvokeRateState(now: t0)
        let peer = RemoteCommandOrigin.mcpPeer(id: "acme")

        // Exhaust the gateway capture bucket (capacity 2).
        XCTAssertTrue(rate.tryConsume(.gateway, .capture, now: t0))
        XCTAssertTrue(rate.tryConsume(.gateway, .capture, now: t0))
        XCTAssertFalse(rate.tryConsume(.gateway, .capture, now: t0))

        // The peer's bucket is created full and independent.
        XCTAssertTrue(rate.tryConsume(peer, .capture, now: t0))
        XCTAssertTrue(rate.tryConsume(peer, .capture, now: t0))
        XCTAssertFalse(rate.tryConsume(peer, .capture, now: t0))

        // Two distinct peers don't share a budget either.
        XCTAssertTrue(rate.tryConsume(.mcpPeer(id: "other"), .capture, now: t0))
    }

    func testTwoArgConvenienceTargetsTheGateway() {
        var rate = RemoteInvokeRateState(now: t0)
        // The legacy two-arg form and the explicit gateway form share one bucket.
        XCTAssertTrue(rate.tryConsume(.capture, now: t0))          // gateway, token 1
        XCTAssertTrue(rate.tryConsume(.gateway, .capture, now: t0)) // gateway, token 2
        XCTAssertFalse(rate.tryConsume(.capture, now: t0))         // gateway exhausted
    }

    // MARK: - Per-origin decide

    func testDecideKeepsGatewayAndPeerBudgetsSeparate() {
        var rate = RemoteInvokeRateState(now: t0)
        func decide(_ cmd: RemoteGlassesCommand, _ origin: RemoteCommandOrigin) -> RemoteCommandPolicy.Decision {
            RemoteCommandPolicy.decide(
                command: cmd, origin: origin, agentModeEnabled: true,
                toggles: .init(observe: true, output: true, capture: true),
                rateState: &rate, now: t0)
        }

        // The gateway spends its whole capture budget...
        XCTAssertEqual(decide(.capturePhoto, .gateway), .allow)
        XCTAssertEqual(decide(.capturePhoto, .gateway), .allow)
        XCTAssertEqual(decide(.capturePhoto, .gateway), .deny(.rateLimited(.capture)))
        // ...the peer is unaffected, and a second peer is independent again.
        XCTAssertEqual(decide(.capturePhoto, .mcpPeer(id: "p1")), .allow)
        XCTAssertEqual(decide(.capturePhoto, .mcpPeer(id: "p2")), .allow)
    }

    func testDefaultOriginMatchesExplicitGateway() {
        var a = RemoteInvokeRateState(now: t0)
        var b = RemoteInvokeRateState(now: t0)
        let toggles = RemoteCommandPolicy.Toggles(observe: true, output: true, capture: true)
        // Same sequence via the default origin and via explicit .gateway → identical decisions.
        for _ in 0..<3 {
            let viaDefault = RemoteCommandPolicy.decide(
                command: .capturePhoto, agentModeEnabled: true, toggles: toggles, rateState: &a, now: t0)
            let viaGateway = RemoteCommandPolicy.decide(
                command: .capturePhoto, origin: .gateway, agentModeEnabled: true, toggles: toggles, rateState: &b, now: t0)
            XCTAssertEqual(viaDefault, viaGateway)
        }
    }

    // MARK: - Audit entry origin + backward-compatible decode

    func testAuditEntryDefaultsOriginToGateway() {
        let entry = RemoteInvokeAuditEntry(action: "device_status", disposition: "allowed")
        XCTAssertEqual(entry.origin, "gateway")
    }

    func testAuditEntryDecodesLegacyRowWithoutOrigin() throws {
        // A row persisted before BN P2 has no `origin` key — it must still load, as the gateway.
        let legacy = Data("""
        {"id":"\(UUID().uuidString)","timestamp":0,"action":"device_status","disposition":"allowed"}
        """.utf8)
        let entry = try JSONDecoder().decode(RemoteInvokeAuditEntry.self, from: legacy)
        XCTAssertEqual(entry.origin, "gateway")
        XCTAssertEqual(entry.action, "device_status")
        XCTAssertEqual(entry.disposition, "allowed")
    }

    func testAuditEntryRoundTripsPeerOrigin() throws {
        let entry = RemoteInvokeAuditEntry(origin: "peer:acme", action: "capture_photo", disposition: "allowed")
        let back = try JSONDecoder().decode(RemoteInvokeAuditEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back, entry)
        XCTAssertEqual(back.origin, "peer:acme")
    }
}
