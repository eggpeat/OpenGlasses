import XCTest
@testable import OpenGlasses

/// Tests for the pure WebRTC frame wire-format decision (binary vs base64-text) and binary framing.
final class WebRTCFrameEncoderTests: XCTestCase {

    func testSmallFrameGoesAsText() {
        XCTAssertFalse(WebRTCFrameEncoder.shouldSendBinary(jpegByteCount: 10_000))
        XCTAssertFalse(WebRTCFrameEncoder.shouldSendBinary(jpegByteCount: WebRTCFrameEncoder.binaryThresholdBytes))
    }

    func testLargeFrameGoesAsBinary() {
        XCTAssertTrue(WebRTCFrameEncoder.shouldSendBinary(jpegByteCount: WebRTCFrameEncoder.binaryThresholdBytes + 1))
        XCTAssertTrue(WebRTCFrameEncoder.shouldSendBinary(jpegByteCount: 200_000))
    }

    func testBinaryMessagePrependsMarker() {
        let jpeg = Data([0xAA, 0xBB, 0xCC])
        let msg = WebRTCFrameEncoder.binaryMessage(jpeg)
        XCTAssertEqual(msg.first, WebRTCFrameEncoder.binaryFrameMarker)
        XCTAssertEqual(msg.count, jpeg.count + 1)
        XCTAssertEqual(Array(msg.dropFirst()), [0xAA, 0xBB, 0xCC])
    }
}
