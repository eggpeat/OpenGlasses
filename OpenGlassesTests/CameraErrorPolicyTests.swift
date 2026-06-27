import MWDATCamera
import XCTest
@testable import OpenGlasses

/// Tests the pure typed-error policy that replaced string-matching on DAT camera errors and decides
/// when a pending photo capture should fail fast (DAT 0.8.0 unified `DatError` model). All
/// `StreamError` cases are constructible without touching `Wearables` (`DeviceIdentifier` is a String).
final class CameraErrorPolicyTests: XCTestCase {

    /// Cases that should abandon a pending capture immediately (the photo won't arrive).
    private let terminal: [StreamError] = [
        .hingesClosed, .timeout, .thermalCritical, .thermalEmergency,
        .peakPowerShutdown, .batteryCritical, .permissionDenied,
        .deviceNotConnected("dev"), .deviceNotFound("dev"),
    ]
    /// Transient cases where the capture or the timeout backstop may still resolve.
    private let transient: [StreamError] = [.internalError, .videoStreamingError]

    func testTerminalErrorsAbortCapture() {
        for error in terminal {
            XCTAssertTrue(CameraErrorPolicy.abortsCapture(error), "\(error) should abort a pending capture")
        }
    }

    func testTransientErrorsDoNotAbortCapture() {
        for error in transient {
            XCTAssertFalse(CameraErrorPolicy.abortsCapture(error), "\(error) should not abort a pending capture")
        }
    }

    func testEveryErrorHasANonEmptyMessage() {
        for error in terminal + transient {
            XCTAssertFalse(CameraErrorPolicy.message(for: error).isEmpty, "\(error) should map to a message")
        }
    }

    func testMessagesAreSpecificForKeyConditions() {
        XCTAssertTrue(CameraErrorPolicy.message(for: .hingesClosed).localizedCaseInsensitiveContains("hinge"))
        XCTAssertTrue(CameraErrorPolicy.message(for: .thermalCritical).localizedCaseInsensitiveContains("hot"))
        XCTAssertTrue(CameraErrorPolicy.message(for: .batteryCritical).localizedCaseInsensitiveContains("battery"))
        XCTAssertTrue(CameraErrorPolicy.message(for: .permissionDenied).localizedCaseInsensitiveContains("permission"))
    }
}
