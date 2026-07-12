import XCTest
@testable import OpenGlasses

@MainActor
final class OpenClawBridgeTests: XCTestCase {

    private let configKeys = [
        "openClawEnabled",
        "openClawConnectionMode",
        "openClawLanHost",
        "openClawPort",
        "openClawTunnelHost",
        "openClawGatewayToken",
    ]

    override func setUp() {
        super.setUp()
        for key in configKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in configKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        let bridge = OpenClawBridge()
        XCTAssertEqual(bridge.lastToolCallStatus, .idle)
        XCTAssertEqual(bridge.connectionState, .notConfigured)
        XCTAssertNil(bridge.resolvedConnection)
    }

    // MARK: - Connection State

    func testConnectionStateEquatable() {
        XCTAssertEqual(OpenClawConnectionState.notConfigured, OpenClawConnectionState.notConfigured)
        XCTAssertEqual(OpenClawConnectionState.checking, OpenClawConnectionState.checking)
        XCTAssertEqual(OpenClawConnectionState.connected, OpenClawConnectionState.connected)
        XCTAssertEqual(OpenClawConnectionState.unreachable("err"), OpenClawConnectionState.unreachable("err"))
        XCTAssertNotEqual(OpenClawConnectionState.notConfigured, OpenClawConnectionState.connected)
        XCTAssertNotEqual(OpenClawConnectionState.unreachable("a"), OpenClawConnectionState.unreachable("b"))
    }

    // MARK: - ResolvedConnection

    func testResolvedConnectionLabels() {
        XCTAssertEqual(ResolvedConnection.lan.label, "LAN")
        XCTAssertEqual(ResolvedConnection.tunnel.label, "Tunnel")
    }

    // MARK: - Endpoint Resolution

    func testResolveEndpointLANMode() async {
        Config.setOpenClawConnectionMode(.lan)
        Config.setOpenClawLanHost("http://192.168.1.50")
        Config.setOpenClawPort(18789)

        let bridge = OpenClawBridge()
        let endpoint = await bridge.resolveEndpoint()

        XCTAssertEqual(endpoint, "http://192.168.1.50:18789")
        XCTAssertEqual(bridge.resolvedConnection, .lan)
    }

    func testResolveEndpointTunnelMode() async {
        Config.setOpenClawConnectionMode(.tunnel)
        Config.setOpenClawTunnelHost("https://my-tunnel.trycloudflare.com")

        let bridge = OpenClawBridge()
        let endpoint = await bridge.resolveEndpoint()

        XCTAssertEqual(endpoint, "https://my-tunnel.trycloudflare.com")
        XCTAssertEqual(bridge.resolvedConnection, .tunnel)
    }

    func testResolveEndpointCachesResult() async {
        Config.setOpenClawConnectionMode(.lan)
        Config.setOpenClawLanHost("http://mac.local")
        Config.setOpenClawPort(18789)

        let bridge = OpenClawBridge()
        let first = await bridge.resolveEndpoint()
        let second = await bridge.resolveEndpoint()

        XCTAssertEqual(first, second, "Cached endpoint should be returned on second call")
    }

    func testClearCachedEndpoint() async {
        Config.setOpenClawConnectionMode(.lan)
        Config.setOpenClawLanHost("http://mac.local")
        Config.setOpenClawPort(18789)

        let bridge = OpenClawBridge()
        let _ = await bridge.resolveEndpoint()
        XCTAssertNotNil(bridge.resolvedConnection)

        bridge.clearCachedEndpoint()
        XCTAssertNil(bridge.resolvedConnection)
    }

    // MARK: - Session Management

    func testResetSessionClearsState() {
        let bridge = OpenClawBridge()
        bridge.resetSession()
        // resetSession should not crash and should work after init
        // The session key changes (internal) — we verify it doesn't crash
        bridge.resetSession()
    }

    // MARK: - Check Connection

    func testCheckConnectionWhenNotConfigured() async {
        Config.setOpenClawEnabled(false)

        let bridge = OpenClawBridge()
        await bridge.checkConnection()

        XCTAssertEqual(bridge.connectionState, .notConfigured)
    }

    // MARK: - Delegate Task with Invalid URL

    func testDelegateTaskFailsGracefully() async {
        // BK P0: delegateTask now fails closed unless Agent Mode is on — enable it so this test
        // exercises the invalid-URL path it's actually about (restored after).
        let priorAgent = Config.agentModeEnabled
        defer { Config.setAgentModeEnabled(priorAgent) }
        Config.setAgentModeEnabled(true)
        // Configure with empty values — URL will be invalid
        Config.setOpenClawEnabled(true)
        Config.setOpenClawGatewayToken("test-token")
        Config.setOpenClawConnectionMode(.lan)
        Config.setOpenClawLanHost("")  // Invalid — no host
        Config.setOpenClawPort(0)

        let bridge = OpenClawBridge()
        bridge.clearCachedEndpoint()

        let result = await bridge.delegateTask(task: "test task")

        switch result {
        case .failure:
            // Expected — invalid URL or connection refused
            break
        case .success:
            // Also acceptable if the empty host resolves to something
            break
        }

        // Status should reflect the attempt
        XCTAssertNotEqual(bridge.lastToolCallStatus, .idle)
    }
}
