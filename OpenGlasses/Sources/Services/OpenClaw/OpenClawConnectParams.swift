import Foundation

/// Pure builder for the `connect` request params both gateway sockets send (the chat socket in
/// `OpenClawBridge` and the event/invoke socket in `OpenClawEventClient`). One builder so the
/// two handshakes can't drift — critical because the device-identity signature covers the
/// clientId/mode/role/scopes carried in the frame, and a mismatch means zero scopes.
///
/// Protocol notes:
/// - `minProtocol 3, maxProtocol 4` — v3 gateways keep working; v4 gateways can use the
///   device-identity and capability fields.
/// - `deviceCapabilities` advertises the remote-invoke command surface up front so the
///   gateway-side agent knows what it can ask for without a round-trip (Plan BH commands).
/// - `device` (present only when the gateway issued a `connect.challenge` nonce) is the signed
///   Ed25519 identity block — remote gateways may grant zero scopes without it.
enum OpenClawConnectParams {

    static let role = "operator"
    static let scopes = ["operator.read", "operator.write"]
    static let clientMode = "node"

    static func build(
        clientId: String,
        displayName: String,
        version: String,
        token: String,
        challengeNonce: String?,
        pairedDeviceId: String? = nil,
        localeIdentifier: String = Locale.current.identifier,
        identity: OpenClawDeviceIdentity.Identity? = nil,
        signedAtMs: Int? = nil
    ) -> [String: Any] {
        var client: [String: Any] = [
            "id": clientId,
            "displayName": displayName,
            "version": version,
            "platform": "ios",
            "mode": clientMode,
        ]
        if let pairedDeviceId, !pairedDeviceId.isEmpty {
            client["deviceId"] = pairedDeviceId
        }

        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 4,
            "role": role,
            "scopes": scopes,
            "client": client,
            "deviceCapabilities": RemoteGlassesCommand.allCanonicalActions,
            "locale": localeIdentifier,
            "auth": ["token": token],
        ]

        if let nonce = challengeNonce, !nonce.isEmpty {
            let signingIdentity = identity ?? OpenClawDeviceIdentity.loadOrCreate()
            let timestamp = signedAtMs ?? Int(Date().timeIntervalSince1970 * 1000)
            if let device = OpenClawDeviceIdentity.connectDevice(
                identity: signingIdentity,
                token: token,
                nonce: nonce,
                clientId: clientId,
                clientMode: clientMode,
                role: role,
                scopes: scopes,
                signedAtMs: timestamp
            ) {
                params["device"] = device
            }
        }
        return params
    }
}
