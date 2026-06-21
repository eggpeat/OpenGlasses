# Plan — EVEN Realities G2 Display Backend (second HUD target)

**Status:** Drafted, not scheduled. Written so it *could* be implemented if we decide to
offer EVEN compatibility. Speculative until there's a device in hand — the protocol is
community reverse-engineered, so treat every byte-level claim as "validate against capture
logs / hardware first."

## Why this might matter

The Ray-Ban Display path is gated behind Meta's DAT dev-mode permission flow (see
`reference_dat_glasses_gotchas` memory) — the single thing blocking real on-glasses
testing. EVEN Realities G2 has **no equivalent gate**: its display speaks an open,
reverse-engineered BLE protocol (`i-soxi/even-g2-protocol`) and there's an official JS
`@evenrealities/even_hub_sdk`. Working community apps (`BondIT-ApS/glass-ai`,
`ukaoma/cos-glasses-server`) already render to it. So EVEN is a way to put our HUD on
*real shipping hardware today*.

The architectural bet: our HUD is already abstracted behind the **SDK-free `HUDScreen`
model** (`HUDScreen` / `HUDLine` / `HUDItem`), which today is rendered two ways — to
`MWDATDisplay` FlexBox on-glasses and to `HUDPreviewView` on-phone. Adding a third
renderer (EVEN) is "another backend behind the same DSL," not a rearchitect. This plan
also *proves* the DSL is genuinely backend-agnostic.

## Hard scope limit (state up front)

**EVEN G2 has no camera.** It is a display + mic + temple-gesture device. So EVEN support
lights up only the HUD/voice/text half of OpenGlasses:

- ✅ Works: AI-response HUD, ambient text, notifications, the Now/Next task cards and the
  launcher (`HUDRouter`/`HUDLauncher`), voice in (G2 mic streams 16 kHz PCM), TTS out.
- ❌ Unavailable on EVEN: camera vision tools, RTMP, face recognition, privacy filter,
  ambient captions sourced from the glasses camera, memory-rewind video — anything that
  needs `CameraService` frames.

The UI must degrade gracefully: with an EVEN device active, camera-dependent tools should
report "not available on this device" rather than fall back to the iPhone camera silently.

## Architecture — the seam

Introduce a backend protocol that `GlassesDisplayService` delegates its actual sends to,
keeping the render queue, interactive gate, and producers exactly as they are:

```swift
protocol GlassesDisplayBackend: AnyObject {
    var isAvailable: Bool { get }            // device present + connected
    func send(_ screen: HUDScreen) async throws
    func showText(_ text: String) async throws
    func clear() async throws
}
```

- `MetaDisplayBackend` — wraps the current `MWDATDisplay` path (`HUDScreen` → FlexBox via
  the existing `makeScreenView` → `Display.send`). Pure refactor; no behaviour change.
- `EvenDisplayBackend` — `HUDScreen` → monochrome 576×288 text layout → even-g2-protocol
  packets over CoreBluetooth.

`GlassesDisplayService` picks the active backend from a setting (`Config.displayBackend`:
`.metaRayBan` default / `.evenG2`). The existing `testRenderSink` / `testCapabilityOverride`
seams stay — they capture at the `HUDScreen`/frame level above the backend, so all current
HUD tests keep working unchanged.

## EVEN G2 protocol (from `i-soxi/even-g2-protocol`, **verify before trusting**)

BLE (base UUID `00002760-08c2-11e1-9073-0e8ac72eXXXX`):
- Discover by advertising name `Even G2_*` (left/right are separate peripherals — pair both).
- Write commands: char `…5401` (handle `0x0842`), write-without-response.
- Notify responses/events: char `…5402` (handle `0x0844`), enable CCCD.
- Display rendering: char `…6402` (handle `0x0864`), 204-byte rendering packets.
- MTU 512; conn interval 7.5–30 ms; custom app-level auth handshake (not BLE pairing) —
  the repo logs a 7-packet handshake (`captures/auth-sequence.log`).

Packet framing:
`[AA] [type] [seq] [len] [pktTotal] [pktSerial] [svcHi] [svcLo] [payload…] [crcLo] [crcHi]`
- `type`: `0x21` command / `0x12` response.
- `len` = payload length + 2 (CRC included).
- `pktTotal`/`pktSerial` for >MTU fragmentation (seq ID constant across a fragmented message).
- CRC-16/CCITT, init `0xFFFF`, poly `0x1021`, computed over **payload only** (skip the
  8-byte header), emitted **little-endian**.

## Files

New (`OpenGlasses/Sources/Services/Display/Even/`):
- `EvenPacket.swift` — pure codec: header build/parse, CRC-16/CCITT, fragmentation. No I/O.
- `EvenScreenRenderer.swift` — pure `HUDScreen` → 576×288 monochrome line layout (reuse the
  existing 120-char body / 40-char title condensing; map `HUDItem`s to a numbered/selectable
  list since there's no rich button styling).
- `EvenBLETransport.swift` — CoreBluetooth: scan `Even G2_*`, connect L/R, auth handshake,
  write to `…5401`/`…6402`, observe `…5402`.
- `EvenDisplayBackend.swift` — ties renderer + transport to `GlassesDisplayBackend`.

Modified:
- `GlassesDisplayService.swift` — extract `GlassesDisplayBackend`; route sends through the
  active backend; add backend selection.
- `Config.swift` — `displayBackend` setting (default `.metaRayBan`).
- Camera-dependent tools — guard on active backend; report unavailable on EVEN.

## Build order (deterministic core first, risky BLE last — per plan-delivery-rhythm)

1. `EvenPacket` codec + CRC, with **golden-vector tests** derived from the repo's
   `captures/*.log` (these give known-good byte sequences without hardware).
2. `EvenScreenRenderer` + snapshot/string tests (HUDScreen → expected 576×288 line layout).
3. `GlassesDisplayBackend` extraction + `MetaDisplayBackend` (refactor; all existing HUD
   tests must stay green).
4. `EvenDisplayBackend` wired to a **mock transport** (records packets) — full headless
   validation of the render→packetize path with no BLE.
5. `EvenBLETransport` (CoreBluetooth) behind the `displayBackend` flag — the only part that
   needs a device. Ships dark until validated on hardware.

## Tests
- CRC-16/CCITT vectors (fixed inputs → known checksums).
- Packet framing + fragmentation round-trips; >512-byte payload splits into N packets with
  constant seq + correct pktTotal/pktSerial.
- `HUDScreen` → renderer layout: title truncation, line wrap at 576px width, item list
  numbering, clear.
- Backend selection: `GlassesDisplayService` routes to the chosen backend; EVEN inactive →
  Meta path unchanged (regression guard for the refactor).
- Mock-transport capture: a task-card `HUDScreen` produces the expected packet stream.

## Open questions / decisions needed
- **Hardware.** None on hand; steps 1–4 are fully testable headless, step 5 is not. Same
  "tests are the gate" posture as the Meta display work.
- **Protocol fragility.** Reverse-engineered and partial (teleprompter/calendar work,
  notifications partial). Text-rendering payload format for `…6402` isn't fully documented —
  needs capture-log analysis or hardware sniffing. May need the official `even_hub_sdk`
  (JS) as a reference oracle.
- **Legal/ToS.** Shipping support for a reverse-engineered BLE protocol — confirm we're
  comfortable. The official SDK is JS-only (not usable from Swift), so a Swift
  reimplementation of the wire protocol is the only native path.
- **Gating.** A device-backend setting, not `agentModeEnabled` — it's not an
  autonomous/gateway feature.
- **Input mapping (Phase 2).** Temple-gesture events arrive on `…5402`; map to the same
  `HUDRouter` selection callbacks the Neural Band drives. Format TBD from capture logs.

## Dependencies / prereqs
- CoreBluetooth (system framework) — **no new SPM dependency**.
- `i-soxi/even-g2-protocol` as the reference spec + capture logs (not a code dependency).
- The `HUDScreen` DSL and `GlassesDisplayService` render queue already exist (Display
  Phases 1–4).

## Why this matters
A second, ungated display backend means we can demo and ship the HUD on real hardware
without waiting on Meta's permission flow — and it forces the HUD layer to stay cleanly
backend-agnostic, which is good hygiene regardless of whether EVEN ever ships. Cost is
bounded and front-loaded into deterministic, testable code; the only hardware-gated piece
(BLE transport) is isolated behind a flag at the very end.
