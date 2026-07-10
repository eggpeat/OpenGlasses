# Consolidated Partials — Outstanding Work Across 🚧 Plans

One place for every **deferred / partial** item pulled out of the in-progress (🚧) plans. The house
style ships a deterministic, headless-tested core first and defers the live edge; this doc gathers
those deferred edges so the remaining work is visible in a single list instead of scattered across
plan docs.

Three buckets, by what unblocks them:

- **A. Buildable now** — headless software follow-ups. These can be picked up as normal one-PR
  sub-plans today; nothing external is required. **This is the actionable backlog.**
- **B. Hardware-pending** — needs the glasses / mic / camera / on-device model / audio routing to
  *do* or *validate*.
- **C. Backend/service-pending** — needs a gateway, relay, or external API to exist/be reachable.

A 🚧 plan whose only remaining work sits in **B** or **C** is **complete to the extent verifiable** —
treat it as done for code purposes; the row is its validation/integration checklist. When a buildable
item (A) lands, or a dependency for B/C appears, work it and update the originating plan doc's status,
then strike it here.

---

## A. Buildable now (headless follow-up PRs)

| Plan | Outstanding item | Notes |
|---|---|---|
| ~~[AU](llm-cost-usage-tracker.md)~~ | ~~Streamed-Chat + realtime-voice token capture~~ | ✅ Shipped — streamed-Chat SSE (`StreamingUsageAccumulator`) + realtime voice (`RealtimeUsage` + `CumulativeUsageMeter`: OpenAI Realtime `response.done`, Gemini Live cumulative `usageMetadata`) |
| ~~[AU](llm-cost-usage-tracker.md)~~ | ~~Settings pricing editor~~ | ✅ Shipped — `ModelPricingEditorView` + persisted `Config.modelPricingOverrides` |
| ~~[AN](projects-scoped-contexts.md)~~ | ~~Shareable project export/import bundle~~ | ✅ Shipped — `ProjectBundle`/`ProjectBundleCodec` + `ProjectExporter`; export (share sheet) in `ProjectDetailView`, import (file picker) in `PersonasView` |
| ~~[AB](health-safety-advisor.md)~~ | ~~Broader interaction-rubric coverage~~ | ✅ Shipped — +7 drug classes (statin/nitrate/PDE5/benzo/opioid/methotrexate/lithium) + alcohol; rules for MAOI+SSRI, PDE5+nitrate, methotrexate/lithium+NSAID, opioid+benzo, ACE+K-sparing, NSAID-in-pregnancy, alcohol+sedative, statin+grapefruit |
| [AV](visual-state-memory.md) | Thumbnail injection (second flag) + BrainStore ingest of aged keyframes | Both ride the shipped ring-buffer/builder; text-only context ships today |
| ~~[U](U-structured-capture-flows.md)~~ | ~~No-code capture-flow author UI~~ | ✅ Shipped — pure `CaptureFlowBuilder` (validate + JSON round-trip) + `CaptureFlowAuthorView` (compose steps → export flow JSON) |
| [S](S-plan-then-execute-and-safety-supervisor.md) | Phase 2: ~~LLM complexity classifier~~ ✅ + parallel-safe execution | Classifier shipped (`ComplexityClassifier` + `Config.llmComplexityClassifierEnabled`); parallel-safe concurrent steps still pending (changes the executor model) |
| [T](T-offline-field-queue-and-sync.md) | Durability fixes + `PeerSyncSink` vs BL's `MockOpsPeer` | Moved from C (2026-07-10): BL supplies the target + test double. Prereqs first: `inFlight` startup recovery, launch-time flush, persisted conflict baselines + advance-on-conflict fix, wire `purgeDone`/`prunePhotoEvidence` triggers (policy shipped, never called) |
| [T](T-offline-field-queue-and-sync.md) | Route `SessionLogger` entries through the queue | Plain headless plumbing, mislabeled device-pending before; U's CaptureRecords already flow |
| [U](U-structured-capture-flows.md) | Remaining camera-binding **routing** (scan_code / photo / ocr_text) | Headless half moved from B (2026-07-10): follow the `VisionAssessTool.swift:52` pattern (tool checks for an active step, offers resolved value); accuracy validation stays in B |
| [U](U-structured-capture-flows.md) | `schema_version` + lossy-decode rejection report; typed `captureRecord` OpKind; `SessionExporter` folding | New 2026-07-10: authored flows currently vanish silently on decode failure (`CaptureFlowLibrary.swift:34-50`); records enqueue as untyped `.logEntry` |
| [V](V-mcp-catalogue-and-transport-breadth.md) | Catalog custom auth-header kind (`X-API-Key`) | New 2026-07-10: prerequisite for BL P1 one-tap peer install; transport + manual editor already support arbitrary headers |
| [V](V-mcp-catalogue-and-transport-breadth.md) | `SSETransport` initialize handshake | Moved from C (2026-07-10): buildable headless against BL's `MockOpsPeer`; BL PR2 depends on it |
| [AB](health-safety-advisor.md) | OCR-label `can_i_eat` **build half**: `use_camera` glue over the MedicationIdentifier OCR path (or a `food_label` schema on the AD substrate) | Moved from B (2026-07-10): the camera+OCR plumbing already exists; only label accuracy stays device-gated. Plus the rubric riders: consume `.anticoagulated`, NSAID+asthma rule, `isClassified` unrecognized wording |
| [AU](llm-cost-usage-tracker.md) | Cache-token capture + prefix-overpricing guard + shape-drift "untracked" marker | New 2026-07-10: Anthropic cache fields are invisible to the tracker (largest error source post-BF); a future dated model id silently bills at the family rate |
| [AN](projects-scoped-contexts.md) | **BM P8:** scope `BrainTool`/`TeleprompterTool` to `{active project, global}` | New 2026-07-10: project boundary violated today — `brain ask` in a global chat retrieves every project's docs (`BrainTool.swift:187`, nil namespace = ALL) |
| [AK](standalone-chat-experience.md) | **BM P9:** SSE session seam + fixture tests + mid-stream-error handling + retry policy | New 2026-07-10: partials-as-success truncation, accumulator concatenation, no 429 retry |
| [AJ](additional-capabilities.md) | Adopt `DeviceSessionCoordinator` in `CameraService` + `GlassesDisplayService` | Moved from B (2026-07-10): headless refactor on the fake-session seam; only simultaneous-use validation stays device-bound |
| [AM](embedding-quality-upgrade.md) | Skip-gated contextual A/B benchmark test + debug "Run embedding benchmark" row; grow the corpus to ~20-30 labelled pairs | New 2026-07-10: the cheapest path to the default-flip decision |
| [AJ](additional-capabilities.md) | **BM P10:** owner gate (biometric/PIN) on Settings + Simple-Mode exit | New 2026-07-10: Simple Mode's exit is an unauthenticated toggle exposing decrypted key fields |
| ~~[O](O-document-rag.md)~~ | ~~Standalone `DocumentsView`~~ | ✅ Shipped — global docs manager grouped by project: list / add-text / import-file / delete |
| ~~[AW](skill-self-evolution.md)~~ | ~~User-correction capture signal~~ | ✅ Shipped — pure `UserCorrectionDetector` + `SkillEvolutionService.noteUserTurn` (records a `.userCorrection` sample against the prior exchange), wired into `sendTextMessage`; Agent-Mode-gated |
| ~~[AT](frame-dedup-change-gate.md)~~ | ~~Advanced-threshold Settings control~~ | ✅ Shipped — `LiveVisionSettingsView` (toggle + threshold + heartbeat) under Settings → Advanced. Flipping the default *on* is still device-gated → B |
| [AM](embedding-quality-upgrade.md) | Optional bundled MiniLM Core ML path | Gated on the `recall@k` benchmark showing a lift; the `EmbeddingBackend` seam is in place |
| [AJ](additional-capabilities.md) | Declarative HUD widget board (#7) | Display Phase-5 concept; defer until X/Y are fully exercised and a concrete multi-widget use case exists |

## B. Hardware-pending (glasses · mic · camera · on-device model · audio routing)

| Plan | Shipped core | Live edge remaining | Validate with |
|---|---|---|---|
| [AP](audio-session-resilience-p2.md) | `AudioInterruptionPolicy` + `AudioRoutePolicy` + permanent engine + generation counters (20 tests) | Recovery firing on real OS interruptions + route flips; phone-speaker fallback selection | A real call/Siri interruption + BT↔speaker route change on device |
| [AS](audio-session-lease-coordinator.md) | `AudioSessionLedger` + `AudioSessionCoordinator` seam (13 tests) | Trim `AppState.switchMode`'s hardware-settling `sleep` | On-device timing across mode switches |
| [AJ](additional-capabilities.md) — shared `DeviceSession` | `DeviceSessionOwnership`/`Coordinator` ref-counting (tested) | **Simultaneous camera+HUD validation only** — coordinator *adoption* in both services moved to bucket A (2026-07-10; the coordinator is dormant code today, zero consumers) | On-glasses camera stream + HUD without contention |
| [AJ](additional-capabilities.md) — alt triggers | Gate + service + shake detector + Settings (16 tests) | Acoustic (`SoundAnalysis`) tuning; AirPod-stem AppIntent (entitlement) | On-device mic tuning; AirPods + entitlement |
| [AJ](additional-capabilities.md) — on-device ASR/TTS | SenseVoice + Kokoro chains, model stores, real inference behind flags (Debug+Release green) | Streaming/VAD endpointing + accuracy; Kokoro audio quality | On-device audio in/out (no simulator path) |
| [AD](structured-vision-assessment.md) | Structured-vision substrate + `vision_assess` + consumers (60 tests) | Assessment **accuracy** on real camera frames | On-glasses camera vs real instruments/scenes |
| [AV](visual-state-memory.md) | Ring buffer + builder + gate keyframe feed (12 tests) | On-device describe budget/quality; flip the flag on | Live Gemini session on glasses |
| [AT](frame-dedup-change-gate.md) | `PerceptualHash` + `FrameGate` wired (18 tests) | Flip `frameDedupEnabled` default on after motion sanity-check | Live streaming-vision on device |
| [AB](health-safety-advisor.md) | Rubric + grounding + advisor + tool (14 tests) | OCR-label photo path — **accuracy validation only** (build half moved to bucket A, 2026-07-10) | Glasses camera + a real food/drug label |
| [U](U-structured-capture-flows.md) | `CaptureFlow` + runner + `capture_flow` tool (11 tests) | Camera-binding **accuracy validation** only (the routing itself moved to bucket A, 2026-07-10) | On-glasses camera capture |
| [AG](teleprompter.md) | `ScriptAligner`/paginator + audio-paced mode + ingestion (Phases 1–4) | Live streaming-recognition tuning | On-device mic while reading |
| [AF](siri-and-local-server.md) #6 | `LocalServerDiscovery` candidate core (5 tests) + experimental scanner | Live Bonjour mDNS hit-rate | Real LAN with advertising/non-advertising servers |
| [AQ](speaker-diarization.md) | Parser/merger/registry + provider seam (24 tests) | Speaker-naming accuracy on real multi-speaker audio | On-device mic, multiple speakers |
| [X](X-interactive-hud-now-next-tasks.md) | Band card + voice bridge + sources (30 tests) | On-device band free-navigation spike | A Display device |
| [AA](first-aid-assist.md) | CPR metronome + protocol catalog + AED + tool (23 tests) | Metronome timing precision + AED spoken/HUD interplay | On hardware |

## C. Backend / service-pending (gateway · relay · external API)

| Plan | Shipped core | Live edge remaining | Unblocked by |
|---|---|---|---|
| [N](N-remote-agent-harness.md) | Harnesses + registry + tools + **Codex/Claude Code preset adapters** (56 tests) | Gateway `agent.*` + live event stream; **live endpoint verification** of the Codex/Claude REST contracts (adapters + presets built) | Gateway implementing `agent.*` + live events; the real Codex/Claude endpoints to confirm paths against |
| [AR](gateway-device-pairing.md) | `SetupCode`/`GatewayAuthSelector`/`PairingResponseInterpreter` (23 tests) | Live approval round-trip (bootstrap → approve → per-device token) **+ finish the stubbed client half** (wire `startPairing`/`onPairingStatusChange` to Settings, use `payload.url`, accept tokens only mid-bootstrap) | Gateway implementing the v3 pairing handshake (shared-token today) |
| [BH](BH-gateway-remote-invoke.md) | `RemoteCommandParser`/`RemoteCommandPolicy`/`RemoteInvokeReply`/`RemoteCommandExecutor` + audited service, per-class toggles + activity log | Live gateway round-trip; fold in the pre-auth `req`-frame drop, `getTranscript` reclassing, `speak` source attribution, and the origin-aware policy/audit refactor (BL P4 seam) | A gateway that sends `node.invoke`-style frames |
| ~~[T](T-offline-field-queue-and-sync.md)~~ | ~~Networked sync sink~~ | **Moved to bucket A** (2026-07-10) — Plan BL's A2A peer is the target; `MockOpsPeer` makes it headless-buildable | — |
| [AQ](speaker-diarization.md) | Batch path + parser (24 tests) | Live diarized caption **WebSocket** stream | Deepgram live streaming (cloud) |
| [V](V-mcp-catalogue-and-transport-breadth.md) | `MCPCatalog` + transport parsing + `SSEEventParser` (37 tests) | OAuth device-code/PKCE + Keychain refresh only (SSE handshake moved to bucket A, 2026-07-10; deprioritized below the new custom-header item) | A real IdP |
| [M](M-webrtc-infra-and-audio.md) | App-side WebRTC + audio coordinator; M1/M2 reference impls | Deploy signaling relay + TURN (**on-demand only** — meeting-link covers remote; room-token auth is the gate); host the expert web client; on-device echo/precedence | A self-host/compliance customer |
| [AK](standalone-chat-experience.md) | Chat tab + rich rendering + real SSE streaming (Phases 1–3) | **Live-credential smoke only** — the verification bulk moved to headless SSE fixture tests via a session seam (BM P9, 2026-07-10), which also fixes mid-stream-error truncation + per-iteration streaming | Real API keys on device (one smoke) |

---

## D. Device-pending edges of ✅ plans (tracked in README prose only — pointer, 2026-07-10)

Three shipped plans carry a live edge that appears nowhere above because the index scopes to 🚧:
**BD** long-session realtime soak, **BG** on-glasses P2 voice-path smoke test, **BI**
uncertainty-phrase-list tuning. Listed here so the pickup queue is complete.

---

## How to use this

- **Want to ship something today?** Pick from **A** — each is a normal deterministic-core sub-plan PR.
- **Bucket B/C rows are not code debt** — they're the validation/integration checklist for when the
  hardware or backend exists. Most are an afternoon of wiring + validation once the dependency lands.
- When an item is done, update its originating plan doc's status and remove its row here.
