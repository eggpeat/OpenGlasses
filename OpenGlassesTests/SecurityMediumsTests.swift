import XCTest
@testable import OpenGlasses

/// Pure-logic coverage for the audit "security mediums" bundle:
/// gateway-token log redaction and cryptographically-random room tokens.
final class SecurityMediumsTests: XCTestCase {

    // MARK: - LogRedaction

    func testRedactsTokenInWebSocketURLQuery() {
        let url = "wss://gw.example.com/ws?token=super-secret-abc123"
        let redacted = LogRedaction.redact(url)
        XCTAssertFalse(redacted.contains("super-secret-abc123"))
        XCTAssertTrue(redacted.contains("token=\(LogRedaction.mask)"))
        XCTAssertTrue(redacted.hasPrefix("wss://gw.example.com/ws?token="))
    }

    func testRedactsTokenButKeepsOtherQueryParams() {
        let url = "ws://host:8080/ws?token=abc123&room=foo"
        let redacted = LogRedaction.redact(url)
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertTrue(redacted.contains("token=\(LogRedaction.mask)"))
        XCTAssertTrue(redacted.contains("&room=foo"))
    }

    func testRedactsTokenInJSONHandshake() {
        let json = #"{"type":"req","params":{"auth":{"token":"deviceToken-xyz-789"}}}"#
        let redacted = LogRedaction.redact(json)
        XCTAssertFalse(redacted.contains("deviceToken-xyz-789"))
        XCTAssertTrue(redacted.contains(#""token":"\#(LogRedaction.mask)""#))
    }

    func testRedactsTokenInJSONWithWhitespace() {
        let json = #"{ "token" : "spaced-secret" }"#
        let redacted = LogRedaction.redact(json)
        XCTAssertFalse(redacted.contains("spaced-secret"))
    }

    func testLeavesTextWithoutTokenUnchanged() {
        let text = "Connecting to wss://gw.example.com/ws (gateway: Home)"
        XCTAssertEqual(LogRedaction.redact(text), text)
    }

    func testRedactionIsCaseInsensitiveOnQueryKey() {
        let redacted = LogRedaction.redact("wss://h/ws?TOKEN=Secret1")
        XCTAssertFalse(redacted.contains("Secret1"))
    }

    // MARK: - SecureToken

    func testURLSafeStringMatchesKnownVector() {
        // base64("hello") = "aGVsbG8=" → url-safe, unpadded = "aGVsbG8"
        let bytes = Array("hello".utf8)
        XCTAssertEqual(SecureToken.urlSafeString(from: bytes), "aGVsbG8")
    }

    func testURLSafeStringUsesURLSafeAlphabetWithoutPadding() {
        // 0xFB 0xFF 0xBF → standard base64 "+/+/" style bytes to force + and / substitution.
        let encoded = SecureToken.urlSafeString(from: [0xFB, 0xFF, 0xBF])
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }

    func testURLSafeTokenHasExpectedEntropyLength() {
        // 16 bytes → 22 unpadded base64 chars.
        XCTAssertEqual(SecureToken.urlSafe(byteCount: 16).count, 22)
    }

    func testURLSafeTokensAreUnique() {
        let tokens = Set((0..<200).map { _ in SecureToken.urlSafe() })
        XCTAssertEqual(tokens.count, 200, "Room tokens must not collide")
    }

    func testURLSafeTokenIsUnguessablyLong() {
        // The old room code was 6 chars; the new one carries far more entropy.
        XCTAssertGreaterThan(SecureToken.urlSafe().count, 6)
    }
}
