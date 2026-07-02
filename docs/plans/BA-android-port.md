# Plan BA — Android Port (full roadmap to platform parity)

**Strategic fit:** OpenGlasses today is an iOS-only app for Ray-Ban Meta / Oakley Meta glasses. Meta now
ships an **official Android Device Access Toolkit** (same vendor, same device coverage, Display support
from v0.7) — so the one thing that would normally make a smart-glasses port impossible (proprietary
device access) is solved by a first-party SDK we already depend on the iOS twin of. Android is the larger
global handset base and the larger Ray-Ban Meta owner base outside the US. This plan is the route from
"iOS app" to "second first-class native app at feature parity."

**Effort:** Large — this is a platform reimplementation, not a feature. Estimate **3–6 engineer-months to
full parity**, but it front-loads value: a usable cloud-only MVP (Phases 0–3) is **~3–5 weeks**.

**Status:** 📝 Drafted — not scheduled. This is a *parent roadmap*; each phase below is its own milestone
(and likely its own repo/PR stream), not a single PR. House style still holds **within** each phase:
deterministic, headless-testable core first; live/device/backend edge deferred.

---

## The reality check (verified against the codebase)

A scan of the 477 Swift files under `OpenGlasses/Sources` gives the honest shape of the job:

| Bucket | Size | Android reality |
|---|---|---|
| **UI layer** (`import SwiftUI` / `UIKit`) | 143 files | Full rewrite in **Jetpack Compose**. No transpile path; SwiftUI does not port. This is the bulk of the work. |
| **Hardware bridge** (`import MWDAT*`) | **8 files** | Rewrite against the **Android DAT SDK**. Tiny, well-isolated surface: connection, camera, display, session coordinator, error policy. The good news. |
| **On-device ML** (`import MLX*`) | 3 files | No equivalent — MLX is Apple-Silicon only. Needs a different runtime (Phase 7). |
| **Networking / LLM core** | `URLSession`-based (17 sites in `LLMService` alone) | Portable *as design*, not code → OkHttp/Ktor. Protocol shapes, tool schemas, JSON contracts all carry over. |
| **Business logic** (375 × `import Foundation`) | the long tail | Swift→Kotlin transliteration. Tedious but mechanical; the `NativeTool` protocol → registry → router architecture maps cleanly to Kotlin interfaces. 102 native-tool files to triage. |

**Key decision: this is a separate native Kotlin app, with the iOS app as the executable spec.** A shared
Kotlin-Multiplatform (KMP) core was considered and rejected as the *starting* posture: KMP would only
cover the Foundation/business-logic tail, while UI, the hardware bridge, and every Apple-framework feature
still need full Android implementations. The transliteration cost is paid either way; KMP adds build
complexity up front for a benefit that only materialises if both apps are then maintained against a shared
core. **Revisit KMP after Phase 2** if the ported core proves stable enough to be worth dual-sourcing.

---

## Framework portability map

Where each Apple framework the app leans on lands on Android. This is the per-feature risk register.

| iOS framework | Used for | Android target | Risk |
|---|---|---|---|
| `MWDATCore/Camera/Display` | glasses connect, stream, photo, HUD | **DAT for Android** (Maven, GitHub Packages) | Low for connect/camera; **Med for Display** — Android DAT is at v0.3.0 and ships only `mwdat-core` + `mwdat-camera`; no Display module observed yet (see verified API shape below) |
| SwiftUI / UIKit | all UI | Jetpack Compose | Med — volume, not difficulty |
| `URLSession` | LLM + all HTTP | Ktor / OkHttp | Low |
| `Speech` (STT) + wake word | voice loop entry | Android `SpeechRecognizer` / on-device | **High** — different lifecycle, the product's spine |
| `AVSpeechSynthesizer` + ElevenLabs | TTS | Android `TextToSpeech` + ElevenLabs (HTTP, portable) | Med |
| `AVFoundation` audio | session/route/interruption | `AudioManager` / `AudioFocus` / Oboe | **High** — Plans AO/AP/AS resilience work re-fought |
| Vision (7 files) | face rec, OCR, privacy blur, pose | **ML Kit** / MediaPipe | Med — re-implementable, different APIs |
| `NaturalLanguage` embeddings | RAG / memory / skill retrieval | ML Kit / ONNX / sentence-transformers | Med — affects AM/AX/AW |
| MLX (LLM/ASR/TTS on-device) | offline tier | MediaPipe LLM Inference / llama.cpp / ONNX / **Gemini Nano** | High — different engine + model formats |
| HealthKit | fitness coaching | **Health Connect** | Low-Med (good parity) |
| HomeKit | smart-home tool | **No real equivalent** → Google Home / Matter or drop | High |
| CarPlay | in-car HUD/voice | **Android Auto** (separate API) | High — first-class per project |
| AppIntents / Intents (18 files) | Siri shortcuts | App Actions / Assistant | High — different model |
| ActivityKit | Live Activities | Foreground-service notifications | Med |
| WatchConnectivity + Watch app/widgets | wearable companion | **Wear OS** (separate target) | High — whole sub-project |
| EventKit | calendar (proactive alerts, geofence) | Calendar Provider | Low |
| Contacts | multi-channel messaging | Contacts Provider | Low |
| StoreKit | IAP / subscriptions | **Play Billing** | Med — all revenue gating |
| `CryptoKit` (license, egress secrets) | Field Assist license, security | Tink / JCA (Curve25519 available) | Low — keep same key format |
| MapKit | nav / aircraft / vehicle | Maps SDK for Android | Low |
| ShazamKit | (music id) | No equivalent → drop | n/a |
| HaishinKit (RTMP) | broadcast | HaishinKit-Kotlin **or** other RTMP lib | Med |
| WebRTC | expert transport (L/M) | `org.webrtc` (same upstream) | Low-Med |
| `ActivityKit`/widgets | home-screen surface | App Widgets / Glance | Med |

---

## Verified DAT-Android API shape (v0.3.0)

The Kotlin SDK does **not** mirror the iOS API names — confirmed against the published `mwdat-core` /
`mwdat-camera` artifacts and a working MIT-licensed Compose reference app. Capture these in the Kotlin
equivalent of `.claude/rules/dat-conventions.md` during Phase 0:

- **Maven wiring:** `maven.pkg.github.com/facebook/meta-wearables-dat-android`, authed with a GitHub PAT
  (`GITHUB_TOKEN`) in `settings.gradle.kts`. Coordinates `com.meta.wearable:mwdat-core` and `:mwdat-camera`,
  version `0.3.0`. No `mwdat-display` artifact present.
- **Bootstrap order (strict):** request runtime perms (`BLUETOOTH`, `BLUETOOTH_CONNECT`, `INTERNET`) →
  `Wearables.initialize(context)` → start device monitoring. `initialize` must run before *any* Wearables
  call. Device pairing is `Wearables.startRegistration(app)` / `startUnregistration(app)`.
- **Permission gate** (our known "THE blocker"): the SDK ships an ActivityResult contract
  `Wearables.RequestPermissionContract()`; bridge it into Compose via a `registerForActivityResult` launcher
  + a `suspendCancellableCoroutine` so callers can `suspend fun request(Permission): PermissionStatus`.
- **Camera** differs from iOS's `Bool`+publisher model: `Wearables.startStreamSession(context, selector, config)`
  returns a `StreamSession`; frames arrive as a **Kotlin Flow** (`session.videoStream.collect { VideoFrame }`),
  and `session.capturePhoto()` is a **suspend that returns the photo directly** as `PhotoData.Bitmap` /
  `PhotoData.HEIC` (no separate `photoDataPublisher`). Selectors: `AutoDeviceSelector()` → `DeviceSelector`.
- **Audio routing to the glasses mic/speaker** is `AudioManager` Bluetooth-SCO: `MODE_IN_COMMUNICATION` +
  SCO connect, PCM16 mono @ 24 kHz (OpenAI-Realtime-native), `AudioRecord`/`AudioTrack`. The reference uses
  the legacy `startBluetoothSco()`; on API 31+ prefer `setCommunicationDevice(TYPE_BLE_HEADSET)`. This is the
  Android face of the iOS LE-Audio mic-routing gotcha — budget the same care here.

### Reusable patterns (not code — MIT app as a worked example)

A small MIT-licensed reference app demonstrates the bridge end-to-end; treat it as a worked example for
Phase 0/1/8, transliterate rather than vendor (attribute if any snippet is copied):

| Pattern | Phase | What it de-risks |
|---|---|---|
| ActivityResult ↔ Compose permission bridge | 0 | The DAT permission gate — the single biggest connect blocker |
| `initialize` → monitor → register bootstrap sequence | 0 | Ordering bugs that look like "SDK doesn't work" |
| Warm/prepared `StreamSession` for instant photo-after-countdown | 4 | Capture latency without holding a live stream open |
| `AudioIoController` SCO routing + PCM16 24 kHz I/O | 1, 8 | Getting glasses mic/speaker as the realtime audio route |
| Foreground service + wakelock owning mic+SCO+WS | 8 | Conversation surviving screen-lock (our background rule) |
| OkHttp-WebSocket OpenAI Realtime client | 8 | Realtime protocol shape (append/delta) in Kotlin |

Everything above is **bridge/plumbing** reuse. The product surface (multi-LLM core, 36+ tools, vision
verticals, HUD launcher) has no counterpart there and is ours to port from the iOS spec.

## Phased roadmap

Each phase is a shippable milestone. Earlier phases gate later ones; within a phase, build the pure core
+ tests first, defer the device/live edge (per house style).

### Phase 0 — Bridge spike + project skeleton  *(~1 week, de-risks everything)*
Prove the hardware path before porting a line of our own logic.
- New Android Studio / Gradle project; wire the **DAT Android SDK** (GitHub Packages PAT, Maven repo) and
  **MockDeviceKit**.
- Vertical slice against the mock device: register → connect → receive a camera frame → capture a photo →
  push a `Display` HUD view → tear down.
- Establish the equivalents of our SDK conventions doc (`.claude/rules/dat-conventions.md`) for Kotlin —
  seed it from the **Verified DAT-Android API shape** section above.
- **First check:** confirm whether a Display module ships in 0.3.x (none observed at 0.3.0). If not, the HUD
  phases (4) wait on a DAT release that adds it — flag early, don't discover it in Phase 4.
- **Exit:** a throwaway app that connects to a mock (and, on a test handset, a real) pair, streams a frame,
  captures a photo, and — if Display is available — shows a HUD. Confirms device coverage, the permission
  gate, and Display parity (or its absence) firsthand.

### Phase 1 — Core conversational loop, cloud-only  *(~2 weeks)*
The product's spine, no glasses-optional features yet.
- Port `LLMService` multi-provider client (Anthropic / Gemini / OpenAI) over Ktor — streaming + tool-calling.
- Wake word → STT (Android `SpeechRecognizer` first; on-device later) → LLM → TTS (`TextToSpeech` +
  ElevenLabs HTTP). Re-fight a *minimal* slice of the audio-session resilience work (AO/AP/AS) — single
  owner, interruption + route handling.
- `ConversationStore`, `Config`/settings model, API-keys-to-Keystore (mirror Keychain approach).
- **Exit:** talk to the glasses, get a spoken answer, on a phone. Headless tests for the LLM client +
  provider fallbacks (Plan AI parity).

### Phase 2 — NativeTool framework + portable tools  *(~2–3 weeks)*
- Port the `NativeTool` protocol → `NativeToolRegistry` → `NativeToolRouter` (native-first, gateway
  fallback) as Kotlin interfaces.
- Triage the 102 tool files into **portable-now** (pure logic / HTTP: web search, calculators, subnet,
  unit/measurement, vehicle-over-Home-Assistant, weather, reminders-as-data, etc.), **needs-platform-API**
  (calendar, contacts, health, location/geofence, maps), and **needs-later-phase** (camera/vision/HUD).
  Port the portable-now set first.
- Bring across the agent harness + safety supervisor pure cores (Plans N, S, R) — these are mostly
  Foundation logic and gate the autonomous/gateway story (keep gated behind the Android equivalent of
  `agentModeEnabled`).
- **Exit:** a meaningful subset of the 36+ tools working, each headless-tested. *(KMP re-evaluation point.)*

### Phase 3 — Compose UI: main flow + settings + chat  *(~2–3 weeks)*
- Main listening flow (preserve the capsule-button + status-indicator identity; coral AI accent — never
  violet/cyan), onboarding, settings, and the standalone Chat experience (Plan AK) with Markdown rendering
  and streaming.
- **Exit:** shippable **cloud-only MVP** — internal beta candidate. Everything above this line is the
  fast path to "an Android user can use OpenGlasses."

### Phase 4 — Camera + Display HUD features  *(~2–3 weeks)*
- Frame publisher, photo capture, frame throttle/dedup gate (Plan AT), HUD DSL (`HUDScreen`) + the
  interactive HUD tasks/launcher (Plans X/Y) re-rendered through the Android `Display` view types.
- Teleprompter (AG), ambient captions overlay.
- **Exit:** glasses see + show on Android.

### Phase 5 — On-device vision / ML  *(~2–3 weeks)*
- Face recognition + auto-announce, OCR reading tool (A1), privacy blur, structured-vision substrate
  (AD/AC HECA, instrument reading, first-aid triage), pose/fitness form — all re-implemented on **ML Kit /
  MediaPipe**.
- Embedding backend (AM) on an Android embedding model → unblocks RAG (O/P), memory relevance (AX), skill
  retrieval (AW).
- **Exit:** the vision-heavy verticals work.

### Phase 6 — Platform-integration features  *(~2–3 weeks)*
- Health Connect (fitness/health vault B/AB), Calendar Provider (proactive alerts, geofence EventKit
  paths), Contacts (multi-channel messaging), Maps SDK, Play Billing for every IAP/subscription gate
  (Accessibility A, Medical Compliance, Field Assist tiers F/G/H — keep per-region pricing).
- HomeKit tool → Google Home / Matter **or** documented drop; ShazamKit → drop.
- Field Assist license verification (Curve25519 — reuse the existing key format and public key, JCA/Tink).
- **Exit:** the B2B (Field Assist) and consumer-IAP revenue paths are live on Android.

### Phase 7 — On-device inference tier  *(~3–4 weeks, hardest)*
- Replace the MLX paths: on-device LLM (MediaPipe LLM Inference / llama.cpp / Gemini Nano), SenseVoice ASR
  and Kokoro TTS equivalents (the vendored sherpa-onnx already ships an **Android** build — reuse it),
  on-device image generation (AL).
- Re-investigate the background-execution constraint from scratch (Android Foreground Services differ from
  iOS) — guard every local-inference path, mirroring the iOS "cloud-only when backgrounded" rule.
- **Exit:** offline tier reaches iOS parity.

### Phase 8 — Realtime voice + expert transports  *(~2–3 weeks)*
- Gemini Live + OpenAI Realtime sessions (WebSocket + audio) ported.
- Expert transports: Meeting-link (zero-infra, portable), MJPEG viewer, WebRTC (`org.webrtc`), RTMP
  broadcast.
- Usage/cost tracker (AU) capturing streamed + realtime tokens.
- **Exit:** the live/low-latency modes work.

### Phase 9 — Companion surfaces + polish to parity  *(~3–4 weeks)*
- **Wear OS** companion (replaces the watchOS app/widgets), App Widgets / Glance home surfaces, Live-
  Activity-equivalent foreground notifications, Android Auto (replaces CarPlay — first-class per project),
  App Actions / Assistant shortcuts (replaces AppIntents/Siri catalog Z).
- Localization (the iOS app ships ~40 locales — reuse the string catalogs), accessibility pass, Play Store
  listing + release pipeline (replaces Xcode Cloud), share-target (replaces Share Extension).
- **Exit:** **full parity.**

---

## Dependency graph

```
Phase 0 (bridge spike)
   └──> Phase 1 (cloud voice loop)
            └──> Phase 2 (tool framework)  ──(re-evaluate KMP)──┐
                     └──> Phase 3 (Compose UI) ── MVP ship ─────┤
                              ├──> Phase 4 (camera + HUD)        │
                              │        └──> Phase 5 (vision/ML)  │
                              ├──> Phase 6 (platform features + revenue)
                              ├──> Phase 7 (on-device tier)
                              └──> Phase 8 (realtime + transports)
                                       └──> Phase 9 (companions + parity)
```

Phases 4–8 are largely parallelisable once Phase 3 lands. Phase 6 is the one that turns the port from
"works" into "earns."

---

## What we deliberately drop or defer (decide explicitly)

- **HomeKit smart-home tool** — no faithful Android analog; Google Home / Matter is a different surface.
- **ShazamKit** — no equivalent; cut.
- **CarPlay → Android Auto** — not a port, a parallel build; first-class per project, scheduled in Phase 9.
- **Apple Watch → Wear OS** — whole separate sub-project; Phase 9.
- **MLX** — replaced wholesale (Phase 7), not ported.

---

## Open questions

1. **One repo or two?** Separate `OpenGlasses-Android` repo vs. a `/android` directory in this repo.
   (Lean: separate repo — different toolchain, CI, and release cadence; share specs via `docs/`.)
2. **Min Android version** — DAT's stated floor is Android 10, but shipping DAT-Android apps in the wild
   target **`minSdk 31` (Android 12)** in practice (and the modern `AudioManager.setCommunicationDevice`
   SCO-routing path is API-31+ anyway). Lean: hold at 31 unless a concrete lower-device need appears.
3. **On-device LLM engine** — Gemini Nano (Pixel-gated, zero-download) vs. MediaPipe/llama.cpp (universal,
   heavy)? Likely both, device-tiered.
4. **KMP after Phase 2?** — worth dual-sourcing the core, or keep two native codebases and sync via the
   spec? Decide once the ported core is stable.
5. **DAT Android maturity** — Android DAT trails iOS: **v0.3.0 vs iOS 0.8.0**, and the camera/core modules
   ship without a Display module today (see verified API shape below). Connect + camera + photo are proven
   in the field; **Display/HUD parity is the open risk** and gates Phase 4. Validate Display availability
   and WiFi transport in Phase 0 on a test handset before committing the HUD-dependent phases.
6. **Release/CI** — Play Store internal track + Gradle CI to replace Xcode Cloud; signing + App-Group-
   equivalent (no direct analog — re-architect the watch/widget shared state).

---

## Effort summary

| Milestone | Phases | Rough effort | Outcome |
|---|---|---|---|
| **Cloud-only MVP** | 0–3 | ~3–5 weeks | An Android user can talk to their glasses and use core tools |
| **Glasses-complete** | +4, 5 | +4–6 weeks | Camera, HUD, and vision verticals work |
| **Revenue-complete** | +6, 8 | +4–6 weeks | IAP/B2B + realtime/expert modes live |
| **Full parity** | +7, 9 | +6–8 weeks | On-device tier, Wear OS, Android Auto, widgets, localization |

The first row is the one that matters: a ~month of work puts a real, usable OpenGlasses on Android, and
the bridge spike (Phase 0) tells us within a week whether anything downstream is at risk.
