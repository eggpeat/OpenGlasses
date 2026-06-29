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
| [AU](llm-cost-usage-tracker.md) | Streamed-Chat (`onToken`) + realtime-voice token capture | Thread usage out of the SSE reconstructors / realtime sessions; the non-streaming capture + pricing/rollup core shipped |
| [AU](llm-cost-usage-tracker.md) | Settings pricing editor | Pure UI over the existing `ModelPricing.overrides` seam |
| [AN](projects-scoped-contexts.md) | Shareable project export/import bundle | Persona + its scoped docs, reusing the Plan [Q](Q-vault-and-skills-library-management.md) vault export/import patterns |
| [AB](health-safety-advisor.md) | Broader interaction-rubric coverage | More curated high-severity rules + tests; the pure rubric/grounding core shipped |
| [AV](visual-state-memory.md) | Thumbnail injection (second flag) + BrainStore ingest of aged keyframes | Both ride the shipped ring-buffer/builder; text-only context ships today |
| [U](U-structured-capture-flows.md) | No-code capture-flow author UI | JSON-authored flows ship today; the editor is the fast-follow |
| [S](S-plan-then-execute-and-safety-supervisor.md) | Phase 2: LLM complexity classifier (vs keyword heuristic) + parallel-safe execution | Optional polish over the shipped supervisor/planner |
| [O](O-document-rag.md) | Standalone `DocumentsView` (list / ingest-via-Files / delete) | Mirrors `VaultManagerView`; partially subsumed by AN's `ProjectDetailView`, a global view is still useful |
| [AW](skill-self-evolution.md) | User-correction capture signal | An extra evolution trigger alongside the shipped tool-failure signal |
| [AT](frame-dedup-change-gate.md) | Advanced-threshold Settings control | Trivial UI over the existing `Config.frameDedup*` flags (flipping the default *on* is device-gated → B) |
| [AM](embedding-quality-upgrade.md) | Optional bundled MiniLM Core ML path | Gated on the `recall@k` benchmark showing a lift; the `EmbeddingBackend` seam is in place |
| [AJ](additional-capabilities.md) | Declarative HUD widget board (#7) | Display Phase-5 concept; defer until X/Y are fully exercised and a concrete multi-widget use case exists |

## B. Hardware-pending (glasses · mic · camera · on-device model · audio routing)

| Plan | Shipped core | Live edge remaining | Validate with |
|---|---|---|---|
| [AP](audio-session-resilience-p2.md) | `AudioInterruptionPolicy` + `AudioRoutePolicy` + permanent engine + generation counters (20 tests) | Recovery firing on real OS interruptions + route flips; phone-speaker fallback selection | A real call/Siri interruption + BT↔speaker route change on device |
| [AS](audio-session-lease-coordinator.md) | `AudioSessionLedger` + `AudioSessionCoordinator` seam (13 tests) | Trim `AppState.switchMode`'s hardware-settling `sleep` | On-device timing across mode switches |
| [AJ](additional-capabilities.md) — shared `DeviceSession` | `DeviceSessionOwnership`/`Coordinator` ref-counting (tested) | One shared camera+display `DeviceSession` (camera + HUD at once) | On-glasses camera stream + HUD without contention |
| [AJ](additional-capabilities.md) — alt triggers | Gate + service + shake detector + Settings (16 tests) | Acoustic (`SoundAnalysis`) tuning; AirPod-stem AppIntent (entitlement) | On-device mic tuning; AirPods + entitlement |
| [AJ](additional-capabilities.md) — on-device ASR/TTS | SenseVoice + Kokoro chains, model stores, real inference behind flags (Debug+Release green) | Streaming/VAD endpointing + accuracy; Kokoro audio quality | On-device audio in/out (no simulator path) |
| [AD](structured-vision-assessment.md) | Structured-vision substrate + `vision_assess` + consumers (60 tests) | Assessment **accuracy** on real camera frames | On-glasses camera vs real instruments/scenes |
| [AV](visual-state-memory.md) | Ring buffer + builder + gate keyframe feed (12 tests) | On-device describe budget/quality; flip the flag on | Live Gemini session on glasses |
| [AT](frame-dedup-change-gate.md) | `PerceptualHash` + `FrameGate` wired (18 tests) | Flip `frameDedupEnabled` default on after motion sanity-check | Live streaming-vision on device |
| [AB](health-safety-advisor.md) | Rubric + grounding + advisor + tool (14 tests) | OCR-a-label `can_i_eat` photo path | Glasses camera + a real food/drug label |
| [U](U-structured-capture-flows.md) | `CaptureFlow` + runner + `capture_flow` tool (11 tests) | Route camera bindings to tools (`barcode_or_voice`→scan_code, `photo`→capture) | On-glasses camera capture |
| [AG](teleprompter.md) | `ScriptAligner`/paginator + audio-paced mode + ingestion (Phases 1–4) | Live streaming-recognition tuning | On-device mic while reading |
| [AF](siri-and-local-server.md) #6 | `LocalServerDiscovery` candidate core (5 tests) + experimental scanner | Live Bonjour mDNS hit-rate | Real LAN with advertising/non-advertising servers |
| [AQ](speaker-diarization.md) | Parser/merger/registry + provider seam (24 tests) | Speaker-naming accuracy on real multi-speaker audio | On-device mic, multiple speakers |
| [X](X-interactive-hud-now-next-tasks.md) | Band card + voice bridge + sources (30 tests) | On-device band free-navigation spike | A Display device |
| [AA](first-aid-assist.md) | CPR metronome + protocol catalog + AED + tool (23 tests) | Metronome timing precision + AED spoken/HUD interplay | On hardware |

## C. Backend / service-pending (gateway · relay · external API)

| Plan | Shipped core | Live edge remaining | Unblocked by |
|---|---|---|---|
| [N](N-remote-agent-harness.md) | Harnesses + registry + tools (48 tests) | Gateway `agent.*` + live event stream; Codex-cloud / Claude-remote adapters | Gateway implementing `agent.*` + live events; a reachable Codex/Claude endpoint |
| [AR](gateway-device-pairing.md) | `SetupCode`/`GatewayAuthSelector`/`PairingResponseInterpreter` + UI (23 tests) | Live approval round-trip (bootstrap → approve → per-device token) | Gateway implementing the v3 pairing handshake (shared-token today) |
| [T](T-offline-field-queue-and-sync.md) | `OfflineQueue` + `Reachability` + `SyncEngine` + `ConflictResolver` (13 tests) | A real **networked** sync sink (today's is local/export-only) | An endpoint that accepts queued op uploads |
| [AQ](speaker-diarization.md) | Batch path + parser (24 tests) | Live diarized caption **WebSocket** stream | Deepgram live streaming (cloud) |
| [V](V-mcp-catalogue-and-transport-breadth.md) | `MCPCatalog` + transport parsing + `SSEEventParser` (37 tests) | SSE `initialize` handshake vs a real server; OAuth device-code/PKCE + Keychain refresh | A reachable SSE MCP server; a real IdP |
| [M](M-webrtc-infra-and-audio.md) | App-side WebRTC + audio coordinator; M1/M2 reference impls | Deploy signaling relay + TURN; host the expert web client; on-device echo/precedence | Self-hosted signaling + TURN |

---

## How to use this

- **Want to ship something today?** Pick from **A** — each is a normal deterministic-core sub-plan PR.
- **Bucket B/C rows are not code debt** — they're the validation/integration checklist for when the
  hardware or backend exists. Most are an afternoon of wiring + validation once the dependency lands.
- When an item is done, update its originating plan doc's status and remove its row here.
