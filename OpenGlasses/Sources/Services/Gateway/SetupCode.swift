import Foundation

/// The payload encoded in a gateway **setup code**: where to connect and a one-time bootstrap
/// token to pair with. The gateway shows the code (as text/QR); the app decodes it to begin
/// pairing.
struct SetupCodePayload: Equatable {
    let url: String
    let bootstrapToken: String
}

/// A setup code is `base64(JSON { "url": …, "bootstrapToken": … })`. Pure, fully tested —
/// tolerant of surrounding whitespace/newlines and strict about the required fields.
enum SetupCode {
    static func decode(_ raw: String) -> SetupCodePayload? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let data = Data(base64Encoded: cleaned),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = (json["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty,
              let token = (json["bootstrapToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            return nil
        }
        return SetupCodePayload(url: url, bootstrapToken: token)
    }

    static func encode(_ payload: SetupCodePayload) -> String {
        let json: [String: Any] = ["url": payload.url, "bootstrapToken": payload.bootstrapToken]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return "" }
        return data.base64EncodedString()
    }
}
