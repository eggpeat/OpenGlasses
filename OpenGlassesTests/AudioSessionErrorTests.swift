import XCTest
@testable import OpenGlasses

/// Each `AudioSessionError` case must carry a non-empty, user-meaningful message so a failed
/// audio path can be surfaced or logged clearly instead of as an opaque low-level error.
final class AudioSessionErrorTests: XCTestCase {

    func testEveryCaseHasNonEmptyDescription() {
        let cases: [AudioSessionError] = [
            .microphonePermissionDenied,
            .invalidFormat(context: "playback"),
            .activationFailed("route unavailable")
        ]
        for error in cases {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "\(error) has an empty description")
        }
    }

    func testPermissionMessageMentionsMicrophone() {
        let description = AudioSessionError.microphonePermissionDenied.errorDescription ?? ""
        XCTAssertTrue(description.localizedCaseInsensitiveContains("microphone"))
    }

    func testInvalidFormatMessageNamesContext() {
        let description = AudioSessionError.invalidFormat(context: "capture resampling").errorDescription ?? ""
        XCTAssertTrue(description.contains("capture resampling"))
    }

    func testActivationFailedMessageIncludesDetail() {
        let description = AudioSessionError.activationFailed("route unavailable").errorDescription ?? ""
        XCTAssertTrue(description.contains("route unavailable"))
    }

    func testEquatableConformance() {
        XCTAssertEqual(AudioSessionError.invalidFormat(context: "playback"),
                       .invalidFormat(context: "playback"))
        XCTAssertNotEqual(AudioSessionError.invalidFormat(context: "playback"),
                          .invalidFormat(context: "capture resampling"))
        XCTAssertNotEqual(AudioSessionError.microphonePermissionDenied,
                          .activationFailed("x"))
    }
}
