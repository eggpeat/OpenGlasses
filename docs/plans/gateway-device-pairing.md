# Plan — Gateway Device Pairing (setup-code → approval → per-device token)

**Status:** 📋 Planned (not built). The deterministic core (setup-code parse/encode, auth-mode
selection, response → pairing-state mapping, per-device identity) is fully headless-testable;
only the live approval round-trip is gateway-pending. **Backend prerequisite** — see Open
questions: the gateway must implement the bootstrap → approval → device-token handshake; until
it does, this degrades cleanly to today's shared-token flow.

Today a user connects to an OpenClaw gateway by pasting a **single shared gateway token**
(`GatewayConfig.token`, a `SecureField` in `GatewaySettingsView`). Every device that connects
uses that same secret, so: there's no way to revoke one device without rotating the token for
all of them; the gateway can't tell "OpenGlasses on Greig's iPhone" from any other client; and
onboarding means copy-pasting a long secret by hand. This plan adds a **per-device pairing**
model on top of the existing protocol-v3 handshake: scan/enter a short **setup code**, the
gateway approves the device, and the app stores a **per-device token** scoped to that gateway.

## What we enable
- **One-tap / one-scan onboarding** — enter a setup code (or scan its QR) instead of pasting a
  raw token. The app does the bootstrap handshake and saves the resulting device token itself.
- **Per-device identity & revocation** — each connection carries a stable `deviceId` and a
  device-scoped token, so the gateway can list, name, and revoke individual devices without
  affecting others.
- **Live pairing status in Settings** — the gateway row shows *Connecting → Waiting for
  approval → Paired* (or a clear error), instead of silently failing on a bad token.
- **No regression** — gateways already configured with a shared token keep working unchanged;
  pairing is an additional path, not a replacement.

## How the user interacts
1. Settings → **Gateways** → *Add* → **Pair with setup code**.
2. Paste the setup code, or tap *Scan QR* (the gateway shows one in its admin UI).
3. The row shows **Waiting for approval**; the user approves the device on the gateway.
4. On approval the row flips to **Paired** and the per-device token is saved to that gateway's
   config. Subsequent launches reconnect silently with the device token.
5. Advanced users can still expand **Manual** and paste a shared token + host as today.

## Architecture — the seam
Extend the **existing** `OpenClawEventClient` protocol-v3 handshake rather than forking it. The
client already: responds to a `connect.challenge` event, sends a `connect` request with
`minProtocol/maxProtocol: 3` + `client {…}` + `auth.token`, and parses the `res` ok/error. We
add three things to that flow:

1. **Auth-mode selection** (pure) — choose the credential to send:
   `bootstrap` (one-time, from a setup code, when not yet paired) → `device` (saved per-device
   token) → `shared` (legacy `gateway.token`, the fallback that works today).
2. **Pairing-response handling** — on a successful `res`/`event` that carries a device token,
   persist it to the gateway and surface `.paired`; on a "pending approval" error, surface
   `.waitingApproval` and keep the socket open; map other errors to `.error`.
3. **Pairing status callback** — `onPairingStatusChange: ((PairingStatus) -> Void)?` so
   `GatewaySettingsView` can render live state.

```swift
enum PairingStatus: Equatable {
    case disconnected, connecting, waitingApproval, paired
    case error(String)
}

enum GatewayAuthMode: String { case bootstrap, device, shared }

/// Pure: pick which credential to present given the gateway's current state.
enum GatewayAuthSelector {
    static func mode(for gateway: GatewayConfig) -> GatewayAuthMode { /* … */ }
}

/// Pure: a setup code is base64(JSON { "url": …, "bootstrapToken": … }).
enum SetupCode {
    static func decode(_ raw: String) -> SetupCodePayload?   // trims whitespace, base64+JSON
    static func encode(_ payload: SetupCodePayload) -> String
}
```

## Model (SDK-free, the deterministic core)
- `SetupCodePayload` — `url`, `bootstrapToken`. Value type. `SetupCode.decode/encode` is a pure,
  exhaustively-tested function (trim whitespace/newlines, base64-decode, JSON-parse, validate
  required keys; reject garbage).
- `GatewayAuthMode` + `GatewayAuthSelector.mode(for:)` — pure precedence (`device` if paired,
  else `bootstrap` if a setup code is present, else `shared`). Tested for every combination.
- `PairingResponseInterpreter` — gateway `res`/`event` JSON → `(PairingStatus, deviceToken?)`.
  Recognises an approved response carrying `result.token` (or a `device.paired` event), a
  pending-approval error (by code/message), and generic failures. Pure → heavily tested.
- `GatewayConfig` gains `deviceToken: String`, `deviceId: String` (stable per gateway), and a
  transient `setupCode` used only until pairing completes (cleared on success). `isConfigured`
  becomes true when *either* a device token *or* a shared token is present.

## Credential & identity storage
- **Device token → Keychain** (`KeychainService`), like the Anthropic/Deepgram keys — never
  `@AppStorage`. The setup code's bootstrap token is short-lived and cleared once a device token
  is issued.
- **`deviceId`** — generated once per gateway (UUID), persisted, and sent as the handshake
  `client.id` (and/or a `deviceId` param) so the gateway can name/revoke this specific device.

## Fix folded in (latent multi-gateway bug)
`sendConnectHandshake()` currently hardcodes `auth.token = Config.openClawGatewayToken` (the
legacy global) even though `establishConnection` resolves the **active** `GatewayConfig`. With
multiple gateways or a paired device this sends the wrong credential. This plan threads the
resolved gateway's credential (device token / shared token, per the auth-mode selector) through
the handshake — a correctness fix that pairing depends on anyway.

## Files
New (`OpenGlasses/Sources/Services/Gateway/`):
- `SetupCode.swift` — `SetupCodePayload` + pure decode/encode.
- `GatewayAuthSelector.swift` — `GatewayAuthMode` + pure selection.
- `PairingResponseInterpreter.swift` — pure JSON → `(PairingStatus, deviceToken?)`.

Touch:
- `OpenClawEventClient.swift` — auth-mode-driven handshake credential; pairing-response handling
  in the `res`/`event` branches; `onPairingStatusChange` callback; `startPairing(setupCode:)`.
- `Config.swift` — `GatewayConfig.deviceToken` / `deviceId` / transient `setupCode`; Keychain
  routing for the device token; `isConfigured` update.
- `Views/GatewaySettingsView.swift` — "Pair with setup code" entry (paste + optional QR scan via
  the existing `scan_code` camera path), a live `PairingStatus` row, "Manual" disclosure for the
  shared-token path that exists today.

## Build order (deterministic core first; live approval gateway-pending)
1. **Pure core** — `SetupCode` + `GatewayAuthSelector` + `PairingResponseInterpreter` +
   `GatewayConfig` fields, exhaustively tested (no network). This is the pairing brain.
2. **Handshake wiring** — thread the selected credential + `deviceId` through
   `sendConnectHandshake` (fixes the latent bug); capture a returned device token and persist it;
   emit `PairingStatus`. Reconnect logic unchanged. (Live approval gateway-pending; the
   interpreter is proven in 1.)
3. **Settings UI** — setup-code entry + QR scan + live status row + Manual disclosure.
4. **Polish** — device naming/“rename this device”, re-pair / unpair, surfacing the gateway's
   device list if the backend exposes it.

## Tests
- `SetupCode.decode`: valid payload; whitespace/newline tolerance; non-base64; valid base64 but
  not JSON; JSON missing `url`/`bootstrapToken`; round-trip with `encode`.
- `GatewayAuthSelector`: paired→`device`; setup-code-present-not-paired→`bootstrap`; neither but
  shared token→`shared`; nothing→unconfigured.
- `PairingResponseInterpreter`: approved with `result.token`; `device.paired` event with token;
  pending-approval error (code + message variants); generic error; ok with no token (already
  authenticated). Asserts both the `PairingStatus` and the extracted token.
- `GatewayConfig`: `isConfigured` true for device-token-only and shared-token-only; device token
  routes to Keychain; `deviceId` stable across loads.

## Open questions / decisions needed
- **Backend support (prerequisite).** This requires the OpenClaw gateway to implement the
  bootstrap → approval → device-token handshake over protocol v3 (a setup-code/bootstrap token,
  an approval gate, a returned per-device token, and ideally a `device.paired` event). If the
  gateway only understands shared tokens, build the deterministic core + UI behind a capability
  check and **degrade to the existing shared-token flow** — no user-visible regression. Confirm
  the exact field names (`result.token`, error code for pending) against the gateway before
  wiring step 2.
- **QR vs paste** — paste is the v1 floor (works with no camera/permissions); QR reuses the
  existing `scan_code` camera path and is the nicer onboarding. Ship paste first.
- **Gating** — lives entirely inside the existing gateway settings, which are already an
  agent/gateway surface gated behind `[[feedback_agentic_toggle]]` (`agentModeEnabled`). No new
  top-level gate.
- **Token rotation / unpair** — define what the app does when the gateway revokes a device
  (treat as `.error`, prompt re-pair) and provide an explicit local "unpair" that clears the
  Keychain device token + `deviceId`.

## Dependencies / prereqs
- Existing: `OpenClawEventClient` (protocol-v3 handshake), `GatewayConfig` / multi-gateway
  config, `KeychainService`, `GatewaySettingsView`, the `scan_code` camera path (for QR).
- Gateway-side: the pairing handshake (see Open questions). **No new SPM dependency.**

## Why this matters
Shared secrets don't scale to an always-on, multi-device setup: you can't revoke one device,
the gateway can't tell devices apart, and onboarding is a manual copy-paste. Per-device pairing
makes connecting a glasses client a scan-and-approve, gives the gateway real per-device
identity and revocation, and surfaces clear connection state instead of a silent failure on a
bad token — all as an additive layer over the protocol-v3 handshake already shipping, with the
hard part (code parsing, auth selection, response interpretation) a set of pure, fully-tested
functions that degrade to today's behaviour when the backend hasn't caught up.
