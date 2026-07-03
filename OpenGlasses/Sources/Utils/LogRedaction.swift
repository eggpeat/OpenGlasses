import Foundation

/// Redacts sensitive credentials from strings before they reach the log.
///
/// Gateway tokens historically travelled in the WebSocket URL query string and inside the
/// `connect` handshake JSON, both of which were logged verbatim via `NSLog`. This masks the
/// token value while leaving the surrounding text intact, so logs stay useful for debugging
/// without spilling a bearer credential to the device console / sysdiagnose.
enum LogRedaction {
    static let mask = "***"

    /// Mask the value of any `token=…` query parameter *and* any `"token": "…"` JSON field.
    static func redact(_ text: String) -> String {
        redactJSONToken(redactQueryToken(text))
    }

    /// `…?token=SECRET&x=1` → `…?token=***&x=1` (case-insensitive on the key).
    static func redactQueryToken(_ text: String) -> String {
        replace(in: text, pattern: #"(?i)([?&]token=)[^&\s"']+"#, with: "$1\(mask)")
    }

    /// `"token":"SECRET"` (any surrounding whitespace) → `"token":"***"`.
    static func redactJSONToken(_ text: String) -> String {
        replace(in: text, pattern: #"("token"\s*:\s*")[^"]*(")"#, with: "$1\(mask)$2")
    }

    private static func replace(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
