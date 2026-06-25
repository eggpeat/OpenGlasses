import XCTest
@testable import OpenGlasses

/// Pure pairing core: setup-code decode/encode, auth-mode precedence, and `GatewayConfig`
/// configured-ness with the new device-token path.
final class GatewayPairingCoreTests: XCTestCase {

    // MARK: - SetupCode

    func testDecodeValidSetupCode() {
        let raw = SetupCode.encode(SetupCodePayload(url: "wss://gw.example/ws", bootstrapToken: "boot-123"))
        let decoded = SetupCode.decode(raw)
        XCTAssertEqual(decoded?.url, "wss://gw.example/ws")
        XCTAssertEqual(decoded?.bootstrapToken, "boot-123")
    }

    func testDecodeToleratesSurroundingWhitespace() {
        let raw = SetupCode.encode(SetupCodePayload(url: "wss://x/ws", bootstrapToken: "t"))
        XCTAssertNotNil(SetupCode.decode("  \n\(raw)\n "))
    }

    func testDecodeRejectsNonBase64() {
        XCTAssertNil(SetupCode.decode("!!!not base64!!!"))
        XCTAssertNil(SetupCode.decode(""))
    }

    func testDecodeRejectsValidBase64ThatIsNotJSON() {
        let notJSON = Data("hello world".utf8).base64EncodedString()
        XCTAssertNil(SetupCode.decode(notJSON))
    }

    func testDecodeRejectsMissingFields() {
        let noToken = Data(#"{"url":"wss://x/ws"}"#.utf8).base64EncodedString()
        let noURL = Data(#"{"bootstrapToken":"t"}"#.utf8).base64EncodedString()
        let blank = Data(#"{"url":"","bootstrapToken":"t"}"#.utf8).base64EncodedString()
        XCTAssertNil(SetupCode.decode(noToken))
        XCTAssertNil(SetupCode.decode(noURL))
        XCTAssertNil(SetupCode.decode(blank))
    }

    func testEncodeDecodeRoundTrip() {
        let payload = SetupCodePayload(url: "wss://round/trip", bootstrapToken: "abc-XYZ-789")
        XCTAssertEqual(SetupCode.decode(SetupCode.encode(payload)), payload)
    }

    // MARK: - GatewayAuthSelector

    func testDeviceTokenWins() {
        XCTAssertEqual(
            GatewayAuthSelector.mode(deviceToken: "dev", setupCode: "code", sharedToken: "shared"),
            .device
        )
    }

    func testSetupCodeTriggersBootstrapWhenNotPaired() {
        XCTAssertEqual(
            GatewayAuthSelector.mode(deviceToken: nil, setupCode: "code", sharedToken: "shared"),
            .bootstrap
        )
        XCTAssertEqual(
            GatewayAuthSelector.mode(deviceToken: "", setupCode: "code", sharedToken: ""),
            .bootstrap
        )
    }

    func testFallsBackToShared() {
        XCTAssertEqual(
            GatewayAuthSelector.mode(deviceToken: nil, setupCode: nil, sharedToken: "shared"),
            .shared
        )
        XCTAssertEqual(
            GatewayAuthSelector.mode(deviceToken: "", setupCode: "", sharedToken: ""),
            .shared
        )
    }

    func testCredentialForEachMode() {
        // device
        XCTAssertEqual(
            GatewayAuthSelector.credential(deviceToken: "dev", setupCode: nil, sharedToken: "shared"),
            "dev"
        )
        // bootstrap → the decoded bootstrap token
        let code = SetupCode.encode(SetupCodePayload(url: "wss://x/ws", bootstrapToken: "boot"))
        XCTAssertEqual(
            GatewayAuthSelector.credential(deviceToken: nil, setupCode: code, sharedToken: "shared"),
            "boot"
        )
        // shared
        XCTAssertEqual(
            GatewayAuthSelector.credential(deviceToken: nil, setupCode: nil, sharedToken: "shared"),
            "shared"
        )
    }

    // MARK: - GatewayConfig.isConfigured

    private func gateway(token: String = "", deviceToken: String? = nil,
                         lanHost: String = "host.local") -> GatewayConfig {
        GatewayConfig(
            id: "g1", name: "G", provider: "openclaw", lanHost: lanHost, port: 18789,
            tunnelHost: "", token: token, connectionMode: "lan", enabled: true, priority: 0,
            deviceToken: deviceToken
        )
    }

    func testConfiguredWithSharedTokenOnly() {
        XCTAssertTrue(gateway(token: "shared").isConfigured)
    }

    func testConfiguredWithDeviceTokenOnly() {
        XCTAssertTrue(gateway(token: "", deviceToken: "dev").isConfigured)
    }

    func testNotConfiguredWithoutCredential() {
        XCTAssertFalse(gateway(token: "", deviceToken: nil).isConfigured)
    }

    func testNotConfiguredWithoutHost() {
        XCTAssertFalse(gateway(token: "shared", lanHost: "").isConfigured)
    }
}
