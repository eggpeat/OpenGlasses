import XCTest
@testable import OpenGlasses

/// Maps gateway `res`/`event` JSON to a `PairingOutcome` — the pure interpretation the live
/// `OpenClawEventClient` applies. JSON via `JSONSerialization` so `NSNumber`/`Bool` bridging
/// matches production.
final class PairingResponseInterpreterTests: XCTestCase {

    private func json(_ string: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: string.data(using: .utf8)!)) as? [String: Any] ?? [:]
    }

    func testApprovedResponseWithDeviceTokenPairs() {
        let outcome = PairingResponseInterpreter.interpretResponse(json("""
        {"ok":true,"result":{"token":"device-xyz"}}
        """))
        XCTAssertEqual(outcome.status, .paired)
        XCTAssertEqual(outcome.deviceToken, "device-xyz")
    }

    func testOkWithoutTokenIsAuthenticatedConnect() {
        let outcome = PairingResponseInterpreter.interpretResponse(json(#"{"ok":true}"#))
        XCTAssertEqual(outcome.status, .paired)
        XCTAssertNil(outcome.deviceToken)
    }

    func testPendingApprovalByCode() {
        let outcome = PairingResponseInterpreter.interpretResponse(json("""
        {"ok":false,"error":{"code":"pairing_pending","message":"nope"}}
        """))
        XCTAssertEqual(outcome.status, .waitingApproval)
        XCTAssertNil(outcome.deviceToken)
    }

    func testPendingApprovalByMessage() {
        let outcome = PairingResponseInterpreter.interpretResponse(json("""
        {"ok":false,"error":{"message":"Device pairing requires approval"}}
        """))
        XCTAssertEqual(outcome.status, .waitingApproval)
    }

    func testGenericErrorSurfacesMessage() {
        let outcome = PairingResponseInterpreter.interpretResponse(json("""
        {"ok":false,"error":{"code":"token_invalid","message":"Bad token"}}
        """))
        XCTAssertEqual(outcome.status, .error("Bad token"))
    }

    func testErrorWithNoMessageStillFails() {
        let outcome = PairingResponseInterpreter.interpretResponse(json(#"{"ok":false}"#))
        if case .error = outcome.status { /* ok */ } else {
            XCTFail("Expected an error status, got \(outcome.status)")
        }
    }

    func testPairedEventWithToken() {
        let outcome = PairingResponseInterpreter.interpretPairedEvent(json(#"{"token":"evt-tok"}"#))
        XCTAssertEqual(outcome?.status, .paired)
        XCTAssertEqual(outcome?.deviceToken, "evt-tok")
    }

    func testPairedEventWithoutTokenIsNil() {
        XCTAssertNil(PairingResponseInterpreter.interpretPairedEvent(json("{}")))
    }

    func testIsPendingApprovalHelper() {
        XCTAssertTrue(PairingResponseInterpreter.isPendingApproval(code: "pairing_required", message: ""))
        XCTAssertTrue(PairingResponseInterpreter.isPendingApproval(code: nil, message: "Please APPROVE the device"))
        XCTAssertFalse(PairingResponseInterpreter.isPendingApproval(code: "other", message: "denied"))
    }
}
