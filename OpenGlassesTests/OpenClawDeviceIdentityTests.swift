import XCTest
import CryptoKit
@testable import OpenGlasses

/// Gateway device identity (BH follow-up): the signed Ed25519 block that earns real scopes on
/// remote gateways. Fresh keys throughout — no keychain dependence.
final class OpenClawDeviceIdentityTests: XCTestCase {

    private func freshIdentity() -> OpenClawDeviceIdentity.Identity {
        OpenClawDeviceIdentity.Identity(privateKey: Curve25519.Signing.PrivateKey())
    }

    private func base64URLDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64)
    }

    func testDeviceIdIsSHA256HexOfPublicKey() {
        let identity = freshIdentity()
        let expected = SHA256.hash(data: identity.privateKey.publicKey.rawRepresentation)
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(identity.deviceId, expected)
        XCTAssertEqual(identity.deviceId.count, 64)
    }

    func testPublicKeyIsBase64URLWithoutPadding() {
        let identity = freshIdentity()
        XCTAssertFalse(identity.publicKeyBase64URL.contains("+"))
        XCTAssertFalse(identity.publicKeyBase64URL.contains("/"))
        XCTAssertFalse(identity.publicKeyBase64URL.contains("="))
        XCTAssertEqual(base64URLDecode(identity.publicKeyBase64URL),
                       identity.privateKey.publicKey.rawRepresentation)
    }

    func testSignedPayloadV3FieldOrder() {
        let payload = OpenClawDeviceIdentity.signedPayloadV3(
            deviceId: "dev", clientId: "gateway-client", clientMode: "node",
            role: "operator", scopes: ["operator.read", "operator.write"],
            signedAtMs: 1_234, token: "tok", nonce: "n0nce")
        let fields = payload.components(separatedBy: "|")
        XCTAssertEqual(Array(fields[0...8]),
                       ["v3", "dev", "gateway-client", "node", "operator",
                        "operator.read,operator.write", "1234", "tok", "n0nce"])
        XCTAssertEqual(fields[9], "ios")
        XCTAssertTrue(["iphone", "ipad"].contains(fields[10]))
        XCTAssertEqual(fields.count, 11)
    }

    func testConnectDeviceSignatureVerifiesOverTheV3Payload() throws {
        let identity = freshIdentity()
        let block = try XCTUnwrap(OpenClawDeviceIdentity.connectDevice(
            identity: identity, token: "tok", nonce: "n0nce",
            clientId: "gateway-client", clientMode: "node",
            role: "operator", scopes: ["operator.read", "operator.write"],
            signedAtMs: 99_000))

        XCTAssertEqual(block["id"] as? String, identity.deviceId)
        XCTAssertEqual(block["publicKey"] as? String, identity.publicKeyBase64URL)
        XCTAssertEqual(block["signedAt"] as? Int, 99_000)
        XCTAssertEqual(block["nonce"] as? String, "n0nce")

        let payload = OpenClawDeviceIdentity.signedPayloadV3(
            deviceId: identity.deviceId, clientId: "gateway-client", clientMode: "node",
            role: "operator", scopes: ["operator.read", "operator.write"],
            signedAtMs: 99_000, token: "tok", nonce: "n0nce")
        let signature = try XCTUnwrap(base64URLDecode(try XCTUnwrap(block["signature"] as? String)))
        XCTAssertTrue(identity.privateKey.publicKey.isValidSignature(signature, for: Data(payload.utf8)),
                      "the gateway must be able to verify the signature over exactly the v3 payload")
        // And it must NOT verify over a payload with different connect metadata (no drift).
        let tampered = payload.replacingOccurrences(of: "node", with: "ui")
        XCTAssertFalse(identity.privateKey.publicKey.isValidSignature(signature, for: Data(tampered.utf8)))
    }
}
