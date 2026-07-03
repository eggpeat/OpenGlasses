import Foundation

/// Pure wire-format decision for `WebRTCStreamingService` frame sends. Extracted so the
/// "binary vs base64-text" choice and the binary framing are headless-testable — the old code
/// built the base64+JSON payload for *every* frame and then threw it away for the binary path.
enum WebRTCFrameEncoder {

    /// Frames larger than this go over the socket as raw binary (base64 would inflate them ~33%).
    static let binaryThresholdBytes = 50_000

    static func shouldSendBinary(jpegByteCount: Int) -> Bool {
        jpegByteCount > binaryThresholdBytes
    }

    /// Raw binary message: a 1-byte frame-type marker followed by the JPEG bytes.
    static let binaryFrameMarker: UInt8 = 0x01

    static func binaryMessage(_ jpeg: Data) -> Data {
        var out = Data([binaryFrameMarker])
        out.append(jpeg)
        return out
    }
}
