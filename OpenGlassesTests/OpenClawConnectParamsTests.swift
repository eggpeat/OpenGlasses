import XCTest
import CryptoKit
@testable import OpenGlasses

/// The shared connect-params builder both gateway sockets use — one builder so the handshakes
/// can't drift from what the device-identity signature covers.
final class OpenClawConnectParamsTests: XCTestCase {

    private func build(nonce: String? = nil, pairedDeviceId: String? = nil,
                       identity: OpenClawDeviceIdentity.Identity? = nil) -> [String: Any] {
        OpenClawConnectParams.build(
            clientId: "gateway-client",
            displayName: "OpenGlasses",
            version: "1.0",
            token: "tok",
            challengeNonce: nonce,
            pairedDeviceId: pairedDeviceId,
            localeIdentifier: "en_US",
            identity: identity,
            signedAtMs: 42_000
        )
    }

    func testBaseParamsCarryProtocolRoleScopesAndCapabilities() {
        let params = build()
        XCTAssertEqual(params["minProtocol"] as? Int, 3, "v3 gateways must keep working")
        XCTAssertEqual(params["maxProtocol"] as? Int, 4)
        XCTAssertEqual(params["role"] as? String, "operator")
        XCTAssertEqual(params["scopes"] as? [String], ["operator.read", "operator.write"])
        XCTAssertEqual(params["deviceCapabilities"] as? [String], RemoteGlassesCommand.allCanonicalActions,
                       "the agent learns the invokable command surface at connect time")
        XCTAssertEqual(params["locale"] as? String, "en_US")
        XCTAssertEqual((params["auth"] as? [String: String])?["token"], "tok")
        let client = params["client"] as? [String: Any]
        XCTAssertEqual(client?["id"] as? String, "gateway-client")
        XCTAssertEqual(client?["mode"] as? String, "node")
        XCTAssertNil(client?["deviceId"], "no paired device id → none advertised")
    }

    func testNoNonceMeansNoDeviceBlock() {
        XCTAssertNil(build()["device"], "unchallenged connects stay token-only (v3 behavior)")
    }

    func testPairedDeviceIdIsCarriedOnTheClient() {
        let client = build(pairedDeviceId: "paired-123")["client"] as? [String: Any]
        XCTAssertEqual(client?["deviceId"] as? String, "paired-123")
    }

    func testChallengedConnectCarriesAVerifiableDeviceIdentity() throws {
        let identity = OpenClawDeviceIdentity.Identity(privateKey: Curve25519.Signing.PrivateKey())
        let params = build(nonce: "n0nce", identity: identity)
        let device = try XCTUnwrap(params["device"] as? [String: Any])
        XCTAssertEqual(device["id"] as? String, identity.deviceId)
        XCTAssertEqual(device["nonce"] as? String, "n0nce")

        // The signature must cover the SAME clientId/mode/role/scopes the frame carries —
        // this is the no-drift property the shared builder exists for.
        let payload = OpenClawDeviceIdentity.signedPayloadV3(
            deviceId: identity.deviceId,
            clientId: (params["client"] as? [String: Any])?["id"] as? String ?? "",
            clientMode: (params["client"] as? [String: Any])?["mode"] as? String ?? "",
            role: params["role"] as? String ?? "",
            scopes: params["scopes"] as? [String] ?? [],
            signedAtMs: device["signedAt"] as? Int ?? 0,
            token: "tok",
            nonce: "n0nce")
        var b64 = try XCTUnwrap(device["signature"] as? String)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        let signature = try XCTUnwrap(Data(base64Encoded: b64))
        XCTAssertTrue(identity.privateKey.publicKey.isValidSignature(signature, for: Data(payload.utf8)))
    }

    func testEveryAdvertisedCapabilityRoundTripsThroughTheParser() {
        XCTAssertEqual(RemoteGlassesCommand.allCanonicalActions.count, 17)
        for action in RemoteGlassesCommand.allCanonicalActions {
            let frame: [String: Any] = [
                "type": "req", "id": "x", "method": "node.invoke",
                "params": ["action": action, "text": "t", "source": "de", "target": "en"] as [String: Any],
            ]
            guard case .command(let command)? = RemoteCommandParser.parse(frame)?.outcome else {
                return XCTFail("advertised capability '\(action)' is not parseable")
            }
            XCTAssertEqual(command.canonicalAction, action,
                           "advertised name must be the canonical name the parser produces")
        }
    }
}
