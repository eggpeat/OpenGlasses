# OpenGlasses Feature Plans

Six plans drafted from a survey of the community smart-glasses landscape, plus a B2B field-service direction informed by IT and refrigeration commercial opportunities. Extended in later rounds (G–M) with features unlocked by the shipped engines.

## Status (as of latest)

All plans A–M are **built and merged to `main`** to the extent verifiable without device hardware or external infrastructure. **541 feature tests passing.**

| Plan | Status |
|---|---|
| A1/A2/A3 Accessibility | ✅ Shipped (OCR reading tool, urgency TTS, scene/social assistive modes + HUD toggle) |
| B Personal Health Vault | ✅ Shipped (templates, tool, editor) |
| [First-Aid / Emergency Assist](first-aid-assist.md) | ✅ Shipped — hands-free bystander coach: pure `CPRMetronome` (100–120 bpm, 30:2) + `FirstAidProtocol` catalog (CPR/choking/bleeding/recovery/MARCH, emergency-gate first) + `AEDFinder` (Overpass) + `FirstAidAssistService` + `first_aid` tool (23 tests, Debug+Release green). Advisory, not a medical device; on-device behaviour device-pending. |
| [Personal Health-Safety Advisor](health-safety-advisor.md) | 📋 Planned (not built) — active "is this safe for me?" over the Health Vault: drug-interaction/contraindication/dietary checks with a deterministic high-severity rubric backstopping the LLM. Medical Compliance IAP. |
| C Live Coach | ✅ Shipped (per-domain loop, dedup) |
| D Utilities | ✅ Shipped (OneEuroFilter, aircraft_overhead) |
| E MCP Server | ✅ Shipped (dev-only HTTP server) |
| F Field Assist | ✅ Phases 1–3 shipped (vault, procedures, domain calc, audit/PDF export, escalation) |
| [Safety Assessment (HECA)](safety-assessment.md) | 🚧 PR 1 core shipped on `feat/safety-assessment-heca` — camera High-Energy Control Assessment (EEI/CSRA SIF) built on the structured-vision substrate: `SafetyHazard` 13-catalog + `SafetyReport` + pure HECA `score`/validation + `SafetyAssessmentSchema` (prompt + structured schema) + `SafetyAssessmentService` + Field-Assist-gated `safety_assessment` tool + pure box→rect overlay mapping. **PR 2:** `SafetyAssessmentStore` (persist+history) + `score`/`history` actions + report + evidence-box overlay views. **PR 3 (`feat/heca-export-advisor`):** PDF export (`SafetyReportPDF` + `export`), Field-Assist session-step audit logging, image-seeded **advisor** (`ask`), and tap-to-open "View full report". ✅ **HECA complete** — 46 tests, Debug green. |
| [Structured Vision Assessment](structured-vision-assessment.md) | 🚧 Core shipped on `feat/structured-vision` (Phases 1–3) — reusable **schema-validated** sibling of `analyzeFrame`: frame → typed `AssessmentCard` via forced tool-use → `vision_assess` tool + card + HUD. First-class **"read the instrument"** (`InstrumentReading` + `UnitNormalizer`); built-in `instrument_reading` consumer. 46 tests, Debug+Release green. Deferred to follow-ups: first-aid triage consumer (now unblocked — #82 merged), Gemini `responseSchema`, CaptureFlow `voice_number` auto-fill. Substrate that HECA builds on. |
| G IT/Network pack | ✅ Shipped (vault, 5 procedures, subnet calc) |
| H Custom vault import | ✅ Shipped (validator, importer, manager UI) |
| I Medication Identifier | ✅ Shipped (OCR × Health Vault) |
| J Navigation Assist | ✅ Shipped (hazard loop, frame-quality gate) |
| K Integration & polish | ✅ K1 HUD + transcription, K2 expert bridge + real notifier; K3 (CarPlay heading) is a documented no-op (no heading consumer) |
| L WebRTC transport | ✅ App-side shipped (real RTCPeerConnection, MJPEG/WebRTC selectable). Needs external signaling + TURN to connect. |
| M WebRTC infra + audio | ✅ M3 audio coordinator shipped; M1 signaling server + M2 expert client shipped as reference impls (`docs/webrtc/`). Remaining: deploy infra + on-device echo/precedence testing. |
| Meeting-link connector | ✅ Shipped — zero-infra `meeting_link` transport opens/pages an external Zoom/Teams/Meet/Whereby URL; nothing to self-host. Recommended remote path. |
| O Document RAG | ✅ Shipped (on-device chunking, embedding, retrieval — chat with your files) |
| P Page & section citations | ✅ Shipped (per-page/section citations for Document RAG) |
| [Study Mode (flashcards + quizzes)](study-mode.md) | ✅ Shipped (#88/#89/#90 + scan) — active-recall study on Document RAG/OCR. Deterministic core (`StudyModels` + pure `QuizGrader` + Leitner `SpacedRepetition` + `StudyContentBuilder` + `StudyStore`) + `LLMService.completeStructured` (text→JSON, on-device offline) + `StudyService` (generate + hands-free quiz/flashcard review) + `StudyAnswerMatcher` + `study` tool; 28 tests, Debug green. **Views (#90):** deck list (Settings → Study Mode) + flashcard review (spaced-rep) + quiz (scored, per-option feedback). **Scan source (`feat/study-mode-scan`):** glasses camera → OCR → multi-page scan → make_deck. ✅ Feature-complete. |
| Q Vault & skills-library management | ✅ Shipped (in-app reference editing, vault export round-trip, ClawHub/voice skills export-import) |
| R MCP Egress & Tool-Poisoning Screen | ✅ Shipped (this PR) — `SecretPatterns` + `EgressScreen` + `ToolDefinitionScanner`; per-server egress policy, qualified-name routing, trust UI; 21 tests |
| S Plan-then-Execute & Safety Supervisor | ✅ Phase 1 complete (#57 spine + this PR loop) — deterministic `SafetySupervisor` (subsumes the high-impact gate), `PlanValidator`/`PlanExecutor`, `SafetyRulesView`, plus the live loop: `AgentPlanner` + `AgentComplexity` gate + `AgentRunner` wired into `LLMService` (multi-step → plan/execute, else single-shot). 29 tests. Phase 2 polish (LLM classifier, parallel steps) optional. |
| T Offline Field Queue & Sync | 🚧 Core shipped (this PR) — SQLite `OfflineQueue` (restart-survival, FIFO), `Reachability`, rising-edge `SyncEngine` over a pluggable sink, `ConflictResolver`; offline/reconnect HUD+TTS, photo-upload feed, `SyncStatusView`; 13 tests. Deferred: networked sink + broader op feeds. |
| U Structured Capture-Flow / Action-Form Schema | 🚧 Core shipped (this PR) — `CaptureFlow` JSON schema + library, deterministic `CaptureFlowRunner` (voice/number/enum/photo bindings, validation, required-field enforcement, preconditions), `FieldResolver`, `capture_flow` tool, record → offline queue; 11 tests. Deferred: camera-source routing + author UI. |
| V Curated MCP Catalogue & Transport Breadth | 🚧 Core shipped (this PR) — `MCPCatalog` + bundled `mcp-catalog.json` (HA/Slack/Notion/GitHub/Linear); one-tap install → safe `.redact` `MCPServerConfig` through the existing discovery → Plan R scanner → router path; `MCPTransportKind`/`MCPAuthKind` + `MCPTransport`/`HTTPTransport` (byte-identical) + pure `SSEEventParser`; catalogue UI + prefilled editor; 37 tests. Deferred: live SSE handshake + OAuth device-code flow. |
| W Presence-Aware Agent Throttle | ✅ Shipped (complete) — core (`ThrottlePolicy`/`PresenceMonitor`, 21 tests) + live integration (`LoopThrottle` on `LiveCoachService`/`ProactiveAlertService`; autonomy ceiling in `SafetySupervisor`; `HeldRecommendationStore` surfaced on re-engagement; +15 tests) + **v2**: CoreMotion `motionActive` signal (`MotionActivityProvider`), Assistive Mode (A3) throttled, continuous captions suspend-when-away (`CaptionPresenceGate`); +7 tests (674 total). Nothing outstanding. |
| X Interactive HUD — Now/Next Tasks | ✅ Shipped (#46) — foundation + band card + voice bridge + Playbook/Procedure sources; 30 headless tests. Display Phases 1–3 merged (#42, #45, #46). |
| Y Interactive HUD Launcher | ✅ Shipped (#54, #55) — full launcher: Quick Actions · Workflows · SOPs · Mode/Persona + Resume-task, hand-off to the Plan X card, in-menu voice nav, pagination, on-phone live mirror; 38 tests. |
| Z Shortcuts Catalog | ✅ Shipped on `feat/shortcuts-catalog` — Siri-added shortcuts injected into the agent prompt; 6 tests. |
| [Siri Intents + Local Server](siri-and-local-server.md) | 📋 Planned — extends `claude/siri-meta-glasses-integration-g0q7xf`: persona-targeted Siri intent, conversational follow-up, result snippets, plus local-server connection-test / presets / mDNS discovery for the keyless Custom provider, and unit-test hardening (items 1–7). |
| [Teleprompter](teleprompter.md) | 📋 Planned — hands-free HUD teleprompter; **audio-paced first** (window auto-advances by listening to you — `ScriptAligner`, pure/testable), **vision/OCR capture second**. Scripts from anywhere (Apple Note via Share Sheet / Shortcut, paste, RAG optional); **adjustable speed** live. Deterministic core first; live HUD + streaming recognition device-pending. Pairs with the EVEN backend. |
| [EVEN G2 Display Backend](even-display-backend.md) | 📝 Drafted (not scheduled) — second HUD target behind the `HUDScreen` DSL via reverse-engineered BLE; deterministic codec/renderer first, CoreBluetooth transport behind a flag. Display+voice only (EVEN has no camera). |
| [Provider Auth & Fallbacks](provider-auth-and-fallbacks.md) | 📝 Reference + 2 buildable items — Claude-app Shortcut text fallback (no key/no Mac, text-only) and a Vertex-AI OAuth Gemini provider. Documents why no consumer subscription gives full functionality by login alone. |

Three selectable expert-stream transports: **MJPEG** (same-LAN browser viewer), **Meeting link** (zero-infra — your meeting tool hosts the call; recommended for remote), and **WebRTC** (self-hosted peer-to-peer, needs your own signaling + TURN).

**Genuinely outstanding (cannot be done/tested without hardware or hosting):** for the self-hosted WebRTC path only — deploy the signaling relay + TURN server, host the expert web client, and run on-device echo/precedence + audio-session testing. The Meeting-link transport needs none of this.

---

| Plan | Title | Effort | Strategic fit |
|---|---|---|---|
| [A](A-accessibility-tier.md) | Accessibility Tier (new IAP) | ~3-5 days | New paid track parallel to Medical Compliance |
| [B](B-personal-health-vault.md) | Personal Health Vault | ~1-2 days | Extends Medical Compliance IAP — first applied vault |
| [C](C-live-coach-tool.md) | Live Coach Tool | ~1-2 days | Generic utility — reuses CameraService |
| [D](D-small-utilities-bundle.md) | Small Utilities Bundle | ~1 day | OneEuroFilter + aircraft_overhead + (deferred) DPad |
| [E](E-mcp-server-mode.md) | Claude Code MCP Server Mode | ~2 days | Developer-only (gated behind `agentModeEnabled`) |
| [F](F-field-assist.md) | **Field Assist (B2B)** | ~3 weeks foundation + 1 week per pack | New B2B revenue line — refrigeration, IT, electrical, automotive |

## Round 2 — features unlocked by the shipped engines

A–F are built (A1–A3, B, C, D, E, and Field Assist Phases 1–3). These reuse the now-shipped building blocks — VaultStore + ProcedureRunner, `LLMService.analyzeFrame`, the Assistive ambient loop, `OCRService`, `SessionExporter`, the `ExpertBridge` seam, `OneEuroFilter` — so each is mostly content or wiring, not new infrastructure.

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [G](G-it-network-pack.md) | IT / Network Field Assist Pack | ~1 week | F engine | 2nd B2B vertical; proves multi-pack thesis |
| [H](H-custom-vault-import.md) | Custom / Enterprise Vault Import | ~3-4 days | VaultStore overlay + ProcedureLibrary | Enterprise tier — bring-your-own pack |
| [I](I-medication-identifier.md) | Medication Identifier | ~1-2 days | A1 OCRService + B Health Vault | Consumer cross-feature; reinforces Medical Compliance |
| [J](J-low-vision-navigation.md) | Low-Vision Navigation Assist | ~2-3 days | A3 loop + analyzeFrame + SpeechUrgency | Highest-impact Accessibility use case |
| [K](K-integration-polish.md) | Integration & Polish (A3 HUD, F Phase 5 expert, CarPlay smoothing) | ~half day–1 week | A3, ExpertBridge+WebRTC, OneEuroFilter | Finish/wire shipped capabilities |
| [L](L-webrtc-expert-transport.md) | Real WebRTC Expert Transport (two-way A/V) | ~1.5–2 weeks | Plan K transport seam | Genuine remote-expert collaboration — Field Assist Pro |
| [M](M-webrtc-infra-and-audio.md) | WebRTC signaling relay + expert web client + audio-session coordination | ~3–5 days | Plan L app side | Completes the live WebRTC call loop |

## Round 3 — agent control

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [N](N-remote-agent-harness.md) | Remote Agent Harness (phone-only, harness-agnostic) | ~3–4 days core + ~1–2/adapter | OpenClawBridge + OpenClawEventClient, `agentModeEnabled`, LLMProvider pattern, MeetingSummaryTool | Glasses as a hands-free remote for any coding/agent backend (OpenClaw / Codex / Claude / custom). 🚧 Phases 1–2 shipped — core (`AgentModels`/`AgentHarness`/`AgentSummarizer`/`AgentSessionService`) + `OpenClawAgentHarness` + `code_agent` tool (Agent-Mode-gated); **Phase 2**: `CustomAgentHarness` (URL + auth + JSONPath field mapping), `AgentHarnessRegistry` active-resolution + `switch_harness`, `AgentHarnessSettingsView`; 48 tests. Deferred: gateway `agent.*` live event stream, Codex/Claude adapters (Phase 3), HUD confirm (Phase 4). |

## Round 4 — on-device knowledge

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [O](O-document-rag.md) | Document RAG (chat with your files) | ~3–4 days | SemanticMemoryStore (sqlite + NLEmbedding + cosine), OCRService (A1) | Persistent, retrievable chunked document knowledge — load a manual/PDF and ask about it across sessions. ✅ Shipped |
| [P](P-chunk-citations.md) | Page & section citations for Document RAG | ~0.5 day | Document RAG (O), chunk metadata | Cite the exact page/section behind a RAG answer, not just the file. ✅ Shipped |
| [Q](Q-vault-and-skills-library-management.md) | Vault & skills-library management (edit, export, import) | ~1–1.5 days | VaultStore/VaultImporter, InstalledSkillStore, VoiceSkillStore | Edit vault references in-app; export/import vaults and both skills libraries between devices. ✅ Shipped |

## Round 5 — agentic hardening, MCP safety & field workflows

Drafted from a survey of our own idea-source repo `~/Code/qaeros` (its `plans/` folder), mapped onto the gaps in OpenGlasses' existing MCP client/server, the on-device agent loop, and Field Assist. **qaeros is an idea-source only — `docs/plans/` here is the canonical home for all OpenGlasses plans.** All six are 📋 Planned.

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [R](R-mcp-egress-and-tool-poisoning-screen.md) | MCP Egress & Tool-Poisoning Screen | ~3–4 days | PromptInjectionPolicy, MCPClient, NativeToolRouter | Outbound + discovery-time mirror of the shipped inbound injection defense; the safety prereq for connecting arbitrary MCP servers to an always-on device. ✅ Shipped |
| [S](S-plan-then-execute-and-safety-supervisor.md) | Plan-then-Execute Agent Mode & Runtime Safety Supervisor | ~1.5–2 wks | NativeToolRouter, ToolConfirmationCoordinator, PromptInjectionPolicy, GlassesDisplayService | The agentic spine: deliberate multi-step execution + a deterministic veto + per-turn constraint re-injection. Also the structural answer to prompt injection. ✅ Phase 1 complete (supervisor + validator + executor + rules UI + planner/complexity-gate/runner wired into the live loop). |
| [T](T-offline-field-queue-and-sync.md) | Offline Field Queue & Store-and-Forward Sync | ~4–5 days | FieldSessionService, SessionLogger, PhotoLogTool, SemanticMemoryStore sqlite | Field work without signal; durable local queue + reconnect flush. Unblocks real Field Assist deployment. 🚧 Core shipped (queue + sync engine + reachability + conflict resolver + offline HUD/TTS + photo feed + status UI); networked sink + broader op feeds deferred. |
| [U](U-structured-capture-flows.md) | Structured Capture-Flow / Action-Form Schema | ~1–1.5 wks | ProcedureRunner, scan_code/CapturePhotoTool/EquipmentLookupTool, GeofenceTool | Typed, validated, audit-ready field records (voice/enum/barcode/photo bindings) from one cross-pack template. Turns Field Assist into a product. 🚧 Core shipped (schema + library + runner + resolver + capture_flow tool + record→queue); camera-source routing + author UI deferred. |
| [V](V-mcp-catalogue-and-transport-breadth.md) | Curated MCP Catalogue & Transport Breadth | ~3–4 days | MCPClient, MCPServersView/MCPServerEditorView, Keychain | One-tap install of vetted servers + SSE + OAuth, so hosted MCP servers actually connect. Sequenced after R so convenience never outruns safety. 🚧 Core shipped (catalogue + one-tap install on safe `.redact` policy + transport parsing/selection + SSE parser; live SSE handshake + OAuth deferred). |
| [W](W-presence-aware-agent-throttle.md) | Presence-Aware Agent Throttle | ~2–3 days | LiveCoachService, ProactiveAlertService, wake-word pipeline, Plan S supervisor | Fuse motion/voice/connectivity into an engagement factor; throttle continuous loops and downgrade autonomy when idle. Battery + contextual-safety win. ✅ Shipped (complete: core + live integration + v2 — CoreMotion signal, Assistive Mode throttle, continuous-caption suspend-when-away). |

**Source-mapping (qaeros → OpenGlasses):** R ← `213`/`200`; S ← `214`/`357`/`192`; T ← `369`; U ← `327`/`366`/`552` (+`547` geofenced preconditions); V ← `575` (concept only); W ← `510`. A work-order/dispatch model (`547`/`421`/`354`) is deliberately **deferred** until T/U land.

**Suggested sequence:** R (safety first) → S (agentic spine) → T (offline) → U (capture schema) → V + W (catalogue + throttle polish).

## Round 6 — interactive display (Ray-Ban Display + Neural Band)

Extends the in-lens HUD line from **read-only** (Display Phase 1 ✅ merged in [#42](https://github.com/straff2002/OpenGlasses/pull/42) — AI responses + ambient captions; Phase 2 on branch `display/hud-phase2` — notifications + Navigation Assist) to **interactive**, driven by the Neural Band. Grounded in the actual `MWDATDisplay` 0.7.0 surface: one-way `Display.send(view)` + `Button`/`onClick`/`onTap` callbacks (no raw gesture stream — firmware owns focus/select). Both plans are mostly a HUD interaction layer over task/launcher models the app already ships.

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [X](X-interactive-hud-now-next-tasks.md) | Interactive HUD — Now/Next Tasks (Display Phase 3) | ~3–4 days | GlassesDisplayService, PlaybookStore, FieldAssist ProcedureRunner, wake-word pipeline | First time the user *acts through* the lens: render the active Playbook/Procedure step as a Now/Next card; band buttons (Done/Skip/Back) drive the existing engine transitions. 📋 Planned |
| [Y](Y-interactive-hud-launcher.md) | Interactive HUD Launcher (Display Phase 4) | ~4–6 days | Plan X HUDRouter, Config.quickActions, PlaybookStore, ProcedureLibrary, AppMode/Persona | Band-navigable home on the lens — Quick Actions · Workflows · SOPs · Mode/Persona, all in one release. Input: band + voice + phone. ✅ Shipped |

**Sequence (agreed):** X first (ships hands-free workflow execution and validates band navigation on one card), then Y (the full launcher reuses X's router).

## Round 7 — additional capabilities

A set of self-contained capabilities that build on the shipped engines; each scoped with what's in and out of scope. The highest-value item (a phone-side renderer of the `MWDATDisplay` DSL) shipped as `HUDPreviewView` (Display Phase 4).

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [Additional Capabilities](additional-capabilities.md) | Net-new features over the shipped engines | ~0.5–4 days each | TextToSpeechService, Config/Keychain, GlassesDisplayService + CameraService, BrainStore, WakeWordService | ✅ API keys → Keychain + BrainStore `needs`/follow-ups shipped. 🚧 Shared camera+display `DeviceSession` — coordinator core tested (`DeviceSessionOwnership`/`DeviceSessionCoordinator`), live adoption deferred (device-only). ✅ Kokoro on-device TTS (offline + backgroundable) — selection policy (`TTSEngineSelector`) + bundle descriptor + model store + download + real HuggingFace installer + **vendored sherpa-onnx 1.13.3 + onnxruntime 1.26.0 xcframeworks (`Vendor/SherpaOnnx`) + real `OfflineTts` inference (`KokoroSynthesizer`, `KOKORO_ENABLED`)** + Settings download (47 tests, Debug+Release green). Only on-device audio output remains to validate (no hardware). ✅ On-device ASR (SenseVoice) — `ASREngineSelector` policy + SenseVoice model layer + real `OfflineRecognizer` (`SenseVoiceRecognizer`, `SHERPA_ONNX_ENABLED`, reusing the vendored binary) + `TranscriptionService` wiring + Settings download (25 tests, Debug+Release green); transcription accuracy + VAD streaming device-pending. 🚧 Alternative hands-free triggers (accessibility) — gate + service + shake detector + Settings shipped (16 tests); acoustic/volume detectors device-tuned (deferred). Conditional: multi-user profiles + PIN. Deferred: declarative HUD widget board. |

**Suggested sequence:** HUDPreviewView snapshot tests → ~~API keys → Keychain~~ ✅ → ~~BrainStore `needs`~~ ✅ → ~~Kokoro TTS~~ ✅ → shared `DeviceSession` → ~~alternative triggers~~ 🚧 core → (if shared-device) profiles+PIN → (deferred) widget board.

## Round 8 — standalone phone app & on-device creation

Make OpenGlasses a daily-driver app **even with the glasses off**: a first-class chat experience as the front door, plus the one on-device modality we're missing (image creation) and quality/organizing upgrades to the existing RAG. All four are mostly UI + wiring over already-shipped engines (`ConversationStore`, `LLMService`, `DocumentStore`/`Embedder`, the `Persona` system); the only new SPM dependency is `apple/ml-stable-diffusion` (image gen). All 📋 Planned.

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [Standalone Chat Experience](standalone-chat-experience.md) | First-class Chat tab — live thread, markdown/code rendering, token streaming, per-message actions, doc attach, inline model/persona switch | ~4–6 days | ChatInputBar, ConversationStore, LLMService, MainView, AppAccent | The front door for glasses-off use; turns a more-capable backend into a real chat app |
| [On-Device Image Generation](on-device-image-generation.md) | Offline image creation (Apple `ml-stable-diffusion`, Core ML/ANE) via `image_generate` tool + results sheet (save/share/regenerate) | ~4–6 days | NativeTool/registry, CameraService Photos save, ShareSheet/`pendingShareItem`, model-store patterns | The only on-device AI modality not yet present; fully offline |
| [Embedding Quality Upgrade](embedding-quality-upgrade.md) | `NLContextualEmbedding` (transformer, multilingual) behind the `Embedder` seam + version-stamp/re-embed migration; optional bundled MiniLM Core ML | ~2–3 days | Embedder, DocumentStore (O/P), SemanticMemoryStore, swift-transformers | Sharper RAG + memory recall, esp. multilingual; quality upgrade to shipped features |
| [Projects (scoped contexts)](projects-scoped-contexts.md) | Persona + scoped documents (`namespace`) + persona-tagged conversations in one Project surface; conditional KB advertisement | ~3–4 days | Persona system, DocumentStore `namespace`, ConversationStore | Reusable "load this context" primitive; generalizes the museum-docent idea |

**Suggested sequence:** Standalone Chat (front door) → Projects (scoped contexts the chat lives in) → Embedding upgrade (sharper retrieval for those contexts) → Image Generation (independent; can land any time). Image gen and the embedding upgrade are independent of the chat/projects pair.

## Round 9 — reliability & connectivity hardening

Three self-contained hardening workstreams over already-shipped paths (the gateway client, the live-audio managers, the speech stack). Each is a deterministic, fully-testable core plus a thin live edge that is device-/backend-pending — same posture as the rest of the speech/agent work. **All three shipped and merged to `main`** (#114, #115, #116); the deterministic cores are fully tested, the live edges are device/backend-pending as noted.

| Plan | Title | Status |
|---|---|---|
| [Audio-Session Resilience](audio-session-resilience.md) | Remove 9 force-unwrapped `AVAudioFormat` inits in the two realtime audio managers; typed errors; mic-permission gating; `setActive` fallback | ✅ Shipped ([#114](https://github.com/straff2002/OpenGlasses/pull/114)) — `AudioFormatFactory`/`AudioSessionError`/`AudioSessionActivator`; both realtime managers hardened. 10 tests; Debug+Release green. Nothing deferred. |
| [Audio-Session Resilience P2](audio-session-resilience-p2.md) | Make the two realtime managers **self-healing**: OS interruption + route-change recovery, Bluetooth-HFP/LE input selection + phone-speaker fallback, idempotent engine/node guards + generation counters | 🚧 Core shipped (this branch) — P1 (#114) stopped the crash; P2 stops the *silent dead session*. Pure `AudioInterruptionPolicy` + `AudioRoutePolicy` (15 tests, 20 audio total) + both managers reworked (permanent engine, serial lifecycle queue, idempotent guards, generation counter); Debug+Release green. Live recovery device-pending; cross-subsystem lease coordinator deferred to its own plan. |
| [Speaker Diarization](speaker-diarization.md) | Deepgram "who said what" — diarized live captions + batch-diarized recordings, speaker naming, brain attribution | 🚧 Core shipped ([#115](https://github.com/straff2002/OpenGlasses/pull/115)) — `DeepgramResponseParser`/`SpeakerSegmentMerger`/`SpeakerRegistry`/`PCMConverter` + `DiarizationProvider` seam (24 tests); `DeepgramSTTService`/`DeepgramBatchService` + flag-gated `AmbientCaptionService` path + `DiarizationSettingsView`. Off by default; HIPAA hard-disables. **Deferred (device-pending):** live WebSocket stream + speaker-naming-from-chip on-device validation. |
| [Gateway Device Pairing](gateway-device-pairing.md) | Setup-code → approval → per-device token over the protocol-v3 handshake; per-device identity & revocation | 🚧 Core shipped ([#116](https://github.com/straff2002/OpenGlasses/pull/116)) — `SetupCode`/`GatewayAuthSelector`/`PairingResponseInterpreter` (23 tests) + `GatewayConfig` device fields + handshake credential fix + `GatewaySettingsView` pairing UI. **Deferred (backend-pending):** live approval round-trip needs the gateway to implement the v3 pairing handshake; degrades to the shared-token flow otherwise. |

**Shipped in order:** Audio-Session Resilience (#114) → Speaker Diarization (#115) → Gateway Device Pairing (#116). The deterministic cores landed fully tested; remaining work is the device/backend-pending live edges noted above.

**Follow-up:** [Audio-Session Resilience P2](audio-session-resilience-p2.md) continues the #114 workstream — interruption/route-change recovery and Bluetooth-input selection in the two realtime managers. Same posture: pure policy core first, live wiring device-pending.

**Follow-up:** [Audio-Session Lease Coordinator](audio-session-lease-coordinator.md) — single owner of the shared `AVAudioSession` across the mic-contending subsystems. 🚧 Foundation + all exclusive owners + coexisting riders shipped: pure `AudioSessionLedger` (generation-gated, stale-release-suppressing, + non-exclusive coexisting holds; 13 tests) + `AudioSessionCoordinator` seam (`acquire`/`release`, register-only `assumeOwnership`, `beginCoexisting`/`endCoexisting` + `audioActivity`). Exclusive owners (wake word + the two realtime managers) are arbitrated by one ledger; coexisting riders (live translation, TTS) register without preempting or deactivating, so the coordinator is the complete source of truth. Only remaining item: trimming `AppState.switchMode`'s hardware-settling sleep (on-device validation needed).

## Round 10 — live-vision efficiency & self-improvement

Four self-contained capabilities surfaced by surveying adjacent multimodal-agent work, mapped onto
OpenGlasses' live-vision path, multi-provider billing, and static skills. Each is a deterministic,
fully-testable core first with the model/device edge deferred — same posture as the rest. All 📋 Planned.

| Plan | Title | Effort | Reuses | Strategic fit |
|---|---|---|---|---|
| [Content-Aware Frame Gate](frame-dedup-change-gate.md) | dHash perceptual gate that drops near-duplicate frames before the LLM (adaptive threshold + heartbeat) | ~1–2 days | FrameThrottler, Gemini Live frame path | Cuts the biggest repeated live-session cost — static-scene frames — with a <1 ms/frame pure gate. Foundation for visual state memory. |
| [LLM Cost & Usage Tracker](llm-cost-usage-tracker.md) | Per-session/model token + estimated-spend tracking, surfaced in Insights | ~2–3 days | LLMService usage blocks, InsightsView/InsightsService, on-device SQLite | Table-stakes for a BYO-key multi-provider app; the data already arrives and is discarded today. |
| [Visual State Memory](visual-state-memory.md) | Rolling keyframe scene memory ("what was I just looking at") injected into the live agent | ~3–4 days | Frame Gate (keyframe source), analyzeFrame/structured vision, GeminiLiveSessionManager, BrainStore | Turns stateless per-frame vision into scene continuity — the point of always-on glasses. |
| [Skill Self-Evolution](skill-self-evolution.md) | Learn new skills from failed turns; **propose → human-approve**, Agent-Mode-gated, Plan-R-screened | ~1.5–2 wks | AgentRunner/NativeToolRouter, InstalledSkillStore, Plan R screen, `agentModeEnabled` | The one genuinely self-improving capability; the assistant gets better at what *this* user keeps needing. |

**Suggested sequence:** Frame Gate (cheap, foundational) → Cost Tracker (independent, high-value) →
Visual State Memory (rides the Frame Gate) → Skill Self-Evolution (largest, safety-sensitive; sequence
last). The Frame Gate and Cost Tracker are small single-PR wins; the latter two are richer features.

## Dependency graph

```
Plan F (Phase 1: VaultStore foundation)
   │
   ├──> Plan B (Health Vault — first applied vault)
   │
   ├──> Plan F (Refrigeration pack — first vertical)
   │
   └──> Plan F (additional vertical packs)
```

Plans A, C, D, E are independent and can ship in any order.

## Suggested sequence

1. **D** (1 day) — Low-risk warmup, ships utilities
2. **A2** (half day, inside Plan A) — Urgency TTS, universal upgrade
3. **A1** (1-2 days) — Reading Accessibility Tool
4. **F Phase 1** (1 week) — Generic VaultStore foundation
5. **B** (1-2 days) — Health Vault rides on F Phase 1
6. **F Phase 2** (1.5 weeks) — Refrigeration pack MVP
7. **A3** (1-2 days) — Assistive Modes, closes out Accessibility IAP
8. **F Phase 3** (0.5 weeks) — Escalation architecture stub
9. **F Phase 4** (1 week) — IT pack
10. **C** (1-2 days) — Live Coach
11. **E** (2 days) — MCP Server (dev-only)
12. **F Phase 5** (TBD) — Expert escalation goes live

## Revenue impact, rough

| Plan | Revenue model | Order of magnitude |
|---|---|---|
| A | Accessibility IAP (consumer) | $-$$ |
| B | Bundled with existing Medical Compliance | (uplift only) |
| C | Free | — |
| D | Free | — |
| E | Free (dev-only) | — |
| **F** | **B2B subscription, per-seat** | **$$$-$$$$** |

Plan F is the single largest revenue opportunity. Even one signed refrigeration contractor (~20 techs × $200/mo) is ~$48k/yr in recurring revenue that doesn't require consumer marketing investment.

## Cross-cutting infrastructure

Generic `VaultStore` (built in Plan F Phase 1) is the shared foundation for all domain knowledge bases:

| Vault | Plan | Gating |
|---|---|---|
| `health` | B | Medical Compliance IAP |
| `refrigeration` | F MVP | Field Assist – Refrigeration IAP |
| `it_network` | F v1.1 | Field Assist – IT IAP |
| `electrical` | F v2 | Field Assist – Electrical IAP |
| `automotive` | F v2 | Field Assist – Auto IAP |
| `custom` | F v2 | Enterprise tier |
