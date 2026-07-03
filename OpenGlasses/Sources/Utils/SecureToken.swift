import Foundation

/// Cryptographically-random, URL-safe identifiers for things that must be unguessable —
/// e.g. a WebRTC room code that, on its own, grants a viewer access to the live stream.
enum SecureToken {
    /// A URL-safe token carrying `byteCount` bytes of cryptographic randomness.
    /// 16 bytes → 128 bits of entropy, encoded as 22 URL-safe base64 characters.
    static func urlSafe(byteCount: Int = 16) -> String {
        let count = max(1, byteCount)
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            // Extremely unlikely; fall back to the system RNG (still non-deterministic).
            var rng = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &rng) }
        }
        return urlSafeString(from: bytes)
    }

    /// Pure: encode bytes as unpadded URL-safe base64 (`+` → `-`, `/` → `_`, no `=` padding).
    static func urlSafeString(from bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
