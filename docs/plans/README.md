# OpenGlasses Feature Plans

This is the canonical home for all OpenGlasses feature plans. Plans are lettered in creation order:
**A–Z**, then **AA, AB, AC…** as the alphabet runs out. Each row links to the full plan doc; the
detailed status, scope, and open questions live there. House style: a deterministic, headless-testable
core first, with the live/device/backend edge deferred; one PR per plan.

**Legend:** ✅ Shipped · 🚧 Core shipped / partial (live or follow-up edge deferred) · 📋 Planned · 📝 Drafted (not scheduled)

## Plan index

| Plan | Title | Status |
|---|---|---|
| [A](A-accessibility-tier.md) | Accessibility Tier (IAP) | ✅ Shipped — A1 OCR reading tool, A2 urgency TTS, A3 scene/social assistive modes + HUD toggle |
| [B](B-personal-health-vault.md) | Personal Health Vault | ✅ Shipped — templates, tool, editor (first applied vault) |
| [C](C-live-coach-tool.md) | Live Coach Tool | ✅ Shipped — per-domain loop, dedup |
| [D](D-small-utilities-bundle.md) | Small Utilities Bundle | ✅ Shipped — OneEuroFilter, aircraft_overhead |
| [E](E-mcp-server-mode.md) | Claude Code MCP Server Mode | ✅ Shipped — dev-only HTTP server (gated behind `agentModeEnabled`) |
| [F](F-field-assist.md) | **Field Assist (B2B)** | ✅ Phases 1–3 shipped — vault, procedures, domain calc, audit/PDF export, escalation |
| [G](G-it-network-pack.md) | IT / Network Field Assist Pack | ✅ Shipped — vault, 5 procedures, subnet calc |
| [H](H-custom-vault-import.md) | Custom / Enterprise Vault Import | ✅ Shipped — validator, importer, manager UI |
| [I](I-medication-identifier.md) | Medication Identifier | ✅ Shipped — OCR × Health Vault |
| [J](J-low-vision-navigation.md) | Low-Vision Navigation Assist | ✅ Shipped — hazard loop, frame-quality gate |
| [K](K-integration-polish.md) | Integration & Polish | ✅ Shipped — K1 HUD+transcription, K2 expert bridge+notifier; K3 (CarPlay heading) a documented no-op |
| [L](L-webrtc-expert-transport.md) | Real WebRTC Expert Transport | ✅ App-side shipped (real RTCPeerConnection, MJPEG/WebRTC selectable). Needs external signaling + TURN |
| [M](M-webrtc-infra-and-audio.md) | WebRTC infra + audio | ✅ M3 audio coordinator shipped; M1 signaling + M2 expert client as reference impls (`docs/webrtc/`). Remaining: deploy infra + on-device audio testing |
| [N](N-remote-agent-harness.md) | Remote Agent Harness | 🚧 Phases 1–2 shipped — core + `OpenClawAgentHarness` + `CustomAgentHarness` + registry + `code_agent`/`switch_harness` (48 tests). Deferred: live event stream, Codex/Claude adapters (P3), HUD confirm (P4) |
| [O](O-document-rag.md) | Document RAG (chat with your files) | ✅ Shipped — on-device chunking, embedding, retrieval |
| [P](P-chunk-citations.md) | Page & section citations | ✅ Shipped — per-page/section citations for Document RAG |
| [Q](Q-vault-and-skills-library-management.md) | Vault & skills-library management | ✅ Shipped — in-app reference editing, vault export round-trip, skills export/import |
| [R](R-mcp-egress-and-tool-poisoning-screen.md) | MCP Egress & Tool-Poisoning Screen | ✅ Shipped — `SecretPatterns` + `EgressScreen` + `ToolDefinitionScanner`; per-server egress policy, trust UI (21 tests) |
| [S](S-plan-then-execute-and-safety-supervisor.md) | Plan-then-Execute & Safety Supervisor | ✅ Phase 1 complete — `SafetySupervisor` + `PlanValidator`/`PlanExecutor` + `AgentPlanner`/`AgentRunner` wired into the live loop (29 tests). Phase 2 polish optional |
| [T](T-offline-field-queue-and-sync.md) | Offline Field Queue & Sync | 🚧 Core shipped — SQLite `OfflineQueue` + `Reachability` + `SyncEngine` + `ConflictResolver` + offline HUD/TTS + status UI (13 tests). Deferred: networked sink + broader op feeds |
| [U](U-structured-capture-flows.md) | Structured Capture-Flows | 🚧 Core shipped — `CaptureFlow` schema + `CaptureFlowRunner` (voice/number/enum/photo bindings) + `capture_flow` tool → queue (11 tests). Deferred: camera-source routing + author UI |
| [V](V-mcp-catalogue-and-transport-breadth.md) | Curated MCP Catalogue & Transport Breadth | 🚧 Core shipped — `MCPCatalog` + one-tap install on safe `.redact` policy + transport parsing + `SSEEventParser` (37 tests). Deferred: live SSE handshake + OAuth device-code flow |
| [W](W-presence-aware-agent-throttle.md) | Presence-Aware Agent Throttle | ✅ Shipped (complete) — `ThrottlePolicy`/`PresenceMonitor` + live integration + v2 (CoreMotion signal, Assistive-Mode throttle, caption suspend-when-away); 43 tests across phases |
| [X](X-interactive-hud-now-next-tasks.md) | Interactive HUD — Now/Next Tasks | ✅ Shipped ([#46](https://github.com/straff2002/OpenGlasses/pull/46)) — band card + voice bridge + Playbook/Procedure sources (30 tests) |
| [Y](Y-interactive-hud-launcher.md) | Interactive HUD Launcher | ✅ Shipped ([#54](https://github.com/straff2002/OpenGlasses/pull/54), [#55](https://github.com/straff2002/OpenGlasses/pull/55)) — Quick Actions · Workflows · SOPs · Mode/Persona + resume-task (38 tests) |
| [Z](Z-shortcuts-catalog.md) | Shortcuts Catalog | ✅ Shipped — Siri-added shortcuts injected into the agent prompt (6 tests) |
| [AA](first-aid-assist.md) | First-Aid / Emergency Assist | ✅ Shipped — hands-free bystander coach: `CPRMetronome` + `FirstAidProtocol` catalog + `AEDFinder` + `first_aid` tool (23 tests). Advisory, not a medical device |
| [AB](health-safety-advisor.md) | Personal Health-Safety Advisor | 🚧 Core shipped — `health_check` (`can_i_take`/`can_i_eat`) over the Health Vault: pure `SubstanceCatalog` + `VaultGrounding` + `InteractionRubric` (authoritative high-severity hits) + `HealthSafetyResponseBuilder` (cite + mandatory disclaimer) → `HealthSafetyAdvisor` grounds the LLM long-tail; Medical-Compliance gated (14 tests). Deferred: OCR-label `can_i_eat` photo path; rubric breadth |
| [AC](safety-assessment.md) | Safety Assessment (HECA) | ✅ Complete — camera High-Energy Control Assessment on the structured-vision substrate: 13-hazard catalog + HECA scoring + `safety_assessment` tool + store/history + PDF export + advisor (46 tests) |
| [AD](structured-vision-assessment.md) | Structured Vision Assessment | ✅ Complete — schema-validated `analyzeFrame` sibling → typed `AssessmentCard` via forced tool-use + `vision_assess` + `instrument_reading` + first-aid triage consumers; Gemini `responseSchema` enforced (`GeminiSchemaTranslator`); `voice_number` capture-flow steps auto-filled from an instrument reading (convert + range-validate). 60 tests |
| [AE](study-mode.md) | Study Mode (flashcards + quizzes) | ✅ Shipped ([#88](https://github.com/straff2002/OpenGlasses/pull/88)/[#89](https://github.com/straff2002/OpenGlasses/pull/89)/[#90](https://github.com/straff2002/OpenGlasses/pull/90)) — Leitner spaced-rep core + `study` tool + deck/flashcard/quiz views + glasses-camera scan source (28 tests) |
| [AF](siri-and-local-server.md) | Siri Intents + Local Server | 🚧 Shipped (1–5,7); #6 LAN auto-detect core landed — Siri persona intent + follow-up + snippets (#93/#94), connection-test + presets, and now `LocalServerDiscovery` (pure candidate gen, 5 tests) + experimental `LocalServerScanner` (Bonjour browse + probe) + "Scan local network" button + Info.plist keys. Live mDNS hit-rate is device-pending |
| [AG](teleprompter.md) | Teleprompter | ✅ Built (Phases 1–4) — hands-free HUD teleprompter: pure `ScriptAligner`/`TeleprompterPaginator` core, audio-paced live mode + ingestion (tool/Settings/store/App-Intent/Share Extension), vision/OCR capture. Device-pending: live streaming-recognition tuning |
| [AH](even-display-backend.md) | EVEN G2 Display Backend | 📝 Drafted — second HUD target behind the `HUDScreen` DSL via reverse-engineered BLE; deterministic codec/renderer first. Display+voice only (no camera) |
| [AI](provider-auth-and-fallbacks.md) | Provider Auth & Fallbacks | 📝 Reference + 2 buildable items — Claude-app Shortcut text fallback and a Vertex-AI OAuth Gemini provider |
| [AJ](additional-capabilities.md) | Additional Capabilities | 🚧 Partial — ✅ API keys→Keychain, BrainStore `needs`, Kokoro on-device TTS, SenseVoice on-device ASR, alt hands-free triggers; 🚧 shared camera+display `DeviceSession` (device-pending); deferred: profiles+PIN, widget board |
| [AK](standalone-chat-experience.md) | Standalone Chat Experience | 🚧 Phases 1–3 built ([b7bdacf](https://github.com/straff2002/OpenGlasses/commit/b7bdacf)) — first-class Chat tab (`ChatListView`/`ChatThreadView`/`ChatComposer`), `MarkdownBlockParser` + `MessageContentView` rich rendering, per-message Copy/Edit/Regenerate, doc attach, inline model/persona switch, real SSE streaming (Anthropic + OpenAI-compatible) + local-MLX token callback. Deferred: on-device cloud-streaming runtime verification (needs real keys + network) |
| [AL](on-device-image-generation.md) | On-Device Image Generation | 📋 Planned — offline image creation (Apple `ml-stable-diffusion`, Core ML/ANE) via `image_generate` tool + results sheet |
| [AM](embedding-quality-upgrade.md) | Embedding Quality Upgrade | ✅ Code-complete across 3 PRs — `EmbeddingVersion` + `DocumentStore` self-heal ([#130](https://github.com/straff2002/OpenGlasses/pull/130)); `EmbeddingBackend` seam + `NLContextualEmbedding` transformer + `NLEmbedding` fallback + `recall@k` benchmark ([#131](https://github.com/straff2002/OpenGlasses/pull/131)); `SemanticMemoryStore` routed through the seam (this PR). `Config.contextualEmbeddingEnabled` **default off** — enable on-device to validate the lift. Sharpens RAG, memory, and skill retrieval |
| [AN](projects-scoped-contexts.md) | Projects (scoped contexts) | 🚧 Core shipped — `personaId` on `ConversationThread` (legacy-safe decode) + `threads(forPersona:)`; `DocumentRAGTool` scoped to the active project namespace + `DocumentStore.documentCount/list(namespace:)`; pure `ProjectScope` + `ProjectContextService` KB grounding injected into both prompt builders; `ProjectDetailView` (prompt + scoped docs + scoped chats) + Chat project filter (8 tests). Deferred: shareable project export/import |
| [AO](audio-session-resilience.md) | Audio-Session Resilience | ✅ Shipped ([#114](https://github.com/straff2002/OpenGlasses/pull/114)) — removed 9 force-unwrapped `AVAudioFormat` inits; typed errors; mic-permission gating (10 tests) |
| [AP](audio-session-resilience-p2.md) | Audio-Session Resilience P2 | 🚧 Core shipped — self-healing managers: `AudioInterruptionPolicy` + `AudioRoutePolicy` + permanent engine + generation counters (20 audio tests). Live recovery device-pending |
| [AQ](speaker-diarization.md) | Speaker Diarization | 🚧 Core shipped ([#115](https://github.com/straff2002/OpenGlasses/pull/115)) — Deepgram "who said what": parser/merger/registry + `DiarizationProvider` seam + flag-gated caption path (24 tests). Off by default; HIPAA hard-disables. Deferred: live WebSocket stream |
| [AR](gateway-device-pairing.md) | Gateway Device Pairing | 🚧 Core shipped ([#116](https://github.com/straff2002/OpenGlasses/pull/116)) — `SetupCode`/`GatewayAuthSelector`/`PairingResponseInterpreter` + pairing UI (23 tests). Deferred: live approval round-trip (backend-pending) |
| [AS](audio-session-lease-coordinator.md) | Audio-Session Lease Coordinator | 🚧 Core shipped — single owner of the shared `AVAudioSession`: pure `AudioSessionLedger` + `AudioSessionCoordinator` seam; exclusive owners + coexisting riders (13 tests). Remaining: trim `switchMode` settle sleep (on-device) |
| [AT](frame-dedup-change-gate.md) | Content-Aware Frame Gate | 🚧 Core shipped — pure `PerceptualHash` (dHash) + `FrameGate` (adaptive threshold + heartbeat + dedupRatio) wired into `FrameThrottler` behind `frameDedupEnabled` (default off); foundation for visual state memory (18 tests). Deferred: flip default on after on-device motion check |
| [AU](llm-cost-usage-tracker.md) | LLM Cost & Usage Tracker | 🚧 Core shipped — pure `ModelPricing` (prefix-matched table + override) + `UsageRollup` + SQLite `UsageStore` + `UsageTracker` facade; `LLMService` captures each cloud provider's usage block; "Tokens & estimated cost" section in `InsightsView` (13 tests). Deferred: streamed-Chat + realtime-voice token capture; Settings pricing editor |
| [AV](visual-state-memory.md) | Visual State Memory | 🚧 Core shipped — pure `VisualStateMemory` ring buffer + `VisualContextBuilder` (relative-time "Recent Visual Context") + `VisualStateService` glue (gate keyframe → rate-limited describe → prompt injection, flag-gated `visualStateMemoryEnabled` default off); rides the Frame Gate via `FrameGate.SendReason`/`onKeyframe` (12 tests). Deferred: on-device describe validation + thumbnail injection |
| [AW](skill-self-evolution.md) | Skill Self-Evolution (+ skill retrieval) | 🚧 Retrieval companion **shipped** ([#127](https://github.com/straff2002/OpenGlasses/pull/127)/[#129](https://github.com/straff2002/OpenGlasses/pull/129)); **evolution loop live end-to-end** — `EvolutionTrigger`/`SkillDeduplicator`/`SkillProposal` + `EvolvedSkillStore` + Agent-Mode-gated `SkillEvolutionService`; `NativeToolRouter` capture hook (`ToolFailureFilter`) + `LLMSkillEvolutionAnalyzer` wiring + Suggested-Skills review inbox (21 tests). Deferred: user-correction capture signal |
| [AX](memory-taxonomy.md) | Typed Memory Taxonomy | 🚧 Core shipped ([#128](https://github.com/straff2002/OpenGlasses/pull/128)) — **project-scoped memory** (`ProjectMemory` + `project_note` tool, active-job context) + **relevance retrieval** (activates `SemanticMemoryStore.systemPromptContext(query:)`); both default-on for beta. Re-scoped after audit found most of the taxonomy already existed |
| [AY](memory-recall.md) | Memory, Recall & Self-Improvement | ✅ Shipped (Phases 1–4) — FTS index + query builder + nudge/skill analyzers + insights ([#100](https://github.com/straff2002/OpenGlasses/pull/100)); cross-session `RecallService` + `brain recall` ([#101](https://github.com/straff2002/OpenGlasses/pull/101)) |
| [AZ](vehicle-ev-status.md) | Vehicle / EV Status Tool | ✅ v1 shipped — `vehicle` tool over the Home Assistant path |

**Three selectable expert-stream transports** (Plans L/M + the meeting-link connector): **MJPEG** (same-LAN browser viewer), **Meeting link** (zero-infra — your meeting tool hosts the call; recommended for remote, nothing to self-host), and **WebRTC** (self-hosted peer-to-peer, needs your own signaling + TURN).

**Genuinely outstanding** (cannot be done/tested without hardware or hosting): the self-hosted WebRTC path only — deploy the signaling relay + TURN, host the expert web client, run on-device echo/precedence testing. The Meeting-link transport needs none of this.

**Reading 🚧:** most 🚧 plans ship a complete, tested core and defer only the live edge by design. The
device/backend-pending leftovers across all 🚧 plans are tracked in one place —
**[Device & Backend Validation Backlog](device-backend-backlog.md)** — so "core shipped" is read as
"awaiting hardware/infra," not as unfinished code. Buildable leftovers are caught up as sub-plan PRs in
each plan doc.

---

## How the plans were grouped (rounds)

The lettering above is creation order; the plans were drafted in themed rounds. The detail (effort,
what each reuses, strategic fit) lives in the individual plan docs — this section is just the map and
the suggested sequences.

- **Round 1 — foundation (A–F).** Accessibility tier, Health Vault, Live Coach, Utilities, MCP server, and the B2B **Field Assist** engine. Sequence: D → A2 → A1 → F Phase 1 → B → F Phase 2 → A3 → F Phases 3–5.
- **Round 2 — features unlocked by the shipped engines (G–M).** Reuse VaultStore/ProcedureRunner, `analyzeFrame`, the assistive loop, OCR, the ExpertBridge seam, OneEuroFilter — mostly content/wiring. Adds the IT pack, custom vault import, medication ID, low-vision nav, integration polish, and the WebRTC expert path.
- **Round 3 — agent control (N).** Glasses as a hands-free remote for any coding/agent backend.
- **Round 4 — on-device knowledge (O–Q).** Document RAG + citations + vault/skills-library management.
- **Round 5 — agentic hardening, MCP safety & field workflows (R–W).** Sequence: R (safety first) → S (agentic spine) → T (offline) → U (capture schema) → V + W (catalogue + throttle). A work-order/dispatch model is deferred until T/U land.
- **Round 6 — interactive display (X–Y).** Read-only HUD → interactive, driven by the Neural Band over `MWDATDisplay`. Sequence: X first (validates band nav on one card), then Y (the launcher reuses X's router).
- **Round 7 — additional capabilities (AJ).** Self-contained features over the shipped engines; the phone-side `MWDATDisplay` renderer shipped as `HUDPreviewView`.
- **Round 8 — standalone phone app & on-device creation (AK–AN).** Daily-driver app with glasses off: chat front door, image generation, embedding upgrade, scoped Projects. Sequence: Chat → Projects → Embedding → Image gen (independent).
- **Round 9 — reliability & connectivity hardening (AO–AS).** Audio-session resilience (P1/P2 + lease coordinator), speaker diarization, gateway device pairing. Shipped in order #114 → #115 → #116.
- **Round 10 — live-vision efficiency & self-improvement (AT–AW).** Sequence: Frame Gate → Cost Tracker → Visual State Memory → Skill Self-Evolution (largest, safety-sensitive; sequence last).
- **Round 11 — adaptive long-term memory (AX).** A typed memory layer over the existing stores; re-scoped after a code audit to the real gaps (project-scoped memory + relevance retrofit). Pairs with the Embedding Upgrade (AM) and Visual State Memory (AV).
- **Standalone tools.** First-Aid (AA), HECA (AC), Structured Vision (AD), Study Mode (AE), Memory/Recall (AY), Vehicle (AZ), and the planned/drafted items (AB, AF, AG, AH, AI) sit outside a single round but are indexed and lettered above.

## Dependency graph

```
Plan F (Phase 1: VaultStore foundation)
   │
   ├──> Plan B (Health Vault — first applied vault)
   ├──> Plan F (Refrigeration pack — first vertical)
   └──> Plan F (additional vertical packs)
```

Plans A, C, D, E are independent and can ship in any order. The on-device knowledge/memory line
(O → P → AY → AX) and the embedding upgrade (AM) reinforce each other: AM sharpens retrieval for O/P
(RAG), AX (memory relevance), and AW (skill retrieval).

## Revenue impact, rough

| Plan | Revenue model | Order of magnitude |
|---|---|---|
| A | Accessibility IAP (consumer) | $–$$ |
| B / AB / AC | Bundled with / extends Medical Compliance IAP | (uplift) |
| C / D / E | Free | — |
| **F (+ G, H)** | **B2B subscription, per-seat** | **$$$–$$$$** |

Plan F is the single largest revenue opportunity. Even one signed refrigeration contractor
(~20 techs × $200/mo) is ~$48k/yr in recurring revenue without consumer marketing spend.

## Cross-cutting infrastructure

Generic `VaultStore` (built in Plan F Phase 1) is the shared foundation for all domain knowledge bases:

| Vault | Plan | Gating |
|---|---|---|
| `health` | B | Medical Compliance IAP |
| `refrigeration` | F MVP | Field Assist – Refrigeration IAP |
| `it_network` | G | Field Assist – IT IAP |
| `electrical` | F v2 | Field Assist – Electrical IAP |
| `automotive` | F v2 | Field Assist – Auto IAP |
| `custom` | H | Enterprise tier |
