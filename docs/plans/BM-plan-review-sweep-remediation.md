# Plan BM — Plan-Review Sweep Remediation (2026-07-10)

**Status:** 📋 Planned
**Origin:** The 2026-07-10 code-verified review sweep across every open/partial plan (BJ/BK/BL, AI,
AH, BA, AL, N/BH/AR, T/U/V, AP/AS/AQ/AF, L/M/AB/AU + the consolidated-partials index audit). Each
finding was verified against source with file:line evidence before inclusion; the detailed analysis
lives in each home plan's "2026-07-10" sections — this plan is the *executable* bundle of the
buildable-now fixes. One PR per phase; phases are independent and can ship in any order. **P0 and
P1 first** (a privacy hole and silent data loss respectively).

Sibling plans from the same sweep: [[BN-shared-consent-surface]] (cross-plan consent affordance),
[[BO-realtime-audio-activation]] (post-BJ realtime threading follow-up). Larger re-scopes stay in
their home plans (BJ two-PR redesign, BL transport flip, AQ on-device-first batch diarization, AI
Vertex item, BA roadmap corrections).

---

## P0 — HIPAA diarization guard at the service layer 🔴 Privacy

**The bug.** "HIPAA hard-disables diarization" is a start-time gate, not a runtime invariant:
`Config.isDiarizationConfigured` (includes `!hipaaMode`) is checked only at session start
(`AmbientCaptionService.swift:122`) and in batch; `DeepgramSTTService.start()` checks key presence
only (`DeepgramSTTService.swift:31`) and `sendAudio`/`connect` never re-check. Enabling HIPAA mode
mid-session does **not** stop a running stream — ambient room audio (bystanders' voices) keeps
flowing to Deepgram until captions restart.

**Fix.**
1. Gate `DeepgramSTTService.start()` and `sendAudio` on `Config.isDiarizationConfigured` so frames
   stop the moment HIPAA flips.
2. The HIPAA toggle stops/restarts ambient captions so the live session tears down deterministically.
3. **Bystander-consent copy:** the settings disclosure says only "raw audio is sent to Deepgram" —
   add copy covering other people's voices, two-party-consent jurisdictions, and Deepgram
   retention/training terms; resolve the open "tie into Plan R consent" question. (The app ships a
   *visual* bystander privacy filter with no audio analogue — at minimum acknowledge the asymmetry.)

**Tests.** Fresh service instances, injected seams (never `.shared`): `sendAudio` drops frames once
`hipaaMode` is set; `start()` refuses under HIPAA; the toggle tears down a running session.

---

## P1 — Offline-queue durability (Plan T's restart-survival promise) 🟠 Data loss

**The bugs (all verified).**
- `SyncEngine.flush` marks ops `.inFlight` before the async deliver (`SyncEngine.swift:78`); killed
  mid-delivery they strand forever — `pending()` selects only `'pending'`
  (`OfflineQueue.swift:127-129`) and nothing resets at startup.
- Flush fires only on a reachability *change* (`Reachability.swift:39-42`, `initiallyOnline: true`):
  capture offline → force-quit → relaunch online never syncs.
- `purgeDone()` (`OfflineQueue.swift:82`) and `prunePhotoEvidence` (`:98`) have **zero production
  callers** — the disk-pressure cap exists as code, not behavior.
- `flush()` drains one `pending(limit: 500)` pass without looping.

**Fix.** Startup recovery (`inFlight → pending` on queue open/engine bind); launch-time flush when
online with pending ops; wire purge + prune to post-flush/app-launch triggers; loop flush until
drained (bounded).

**Tests.** Extend `OfflineQueueTests`/`SyncEngineTests`: a strand-then-reopen recovers; bind-while-
online flushes; delivered photos prune past the cap; >500 backlog drains.

---

## P2 — Capture-flow schema safety (Plan U riders) 🟠

**The bugs.** `CaptureFlow` has no version field; `CaptureFlowLibrary.load()` `try?`-decodes and
`compactMap`s failures away silently (`CaptureFlowLibrary.swift:34-50`) — any v2 binding type or a
typo in a hand-edited overlay makes the flow **vanish from the library with no feedback**. Real
migration surface now that `CaptureFlowAuthorView` ships user-authored JSON via share sheet.
CaptureRecords enqueue as bare `.logEntry` (`CaptureFlowService.swift:127`) — indistinguishable to
a future networked sink.

**Fix.** `schema_version` + lossy-decode-with-rejection-report (the `MCPCatalog.loadStrict`
pattern, `MCPCatalog.swift:160-177`) surfaced in the flows UI; a typed `captureRecord` OpKind (or
payload envelope); fold `CaptureRecord` into `SessionExporter` audit JSON (closes U's "audit-ready
record" promise, currently true only via the queue).

**Tests.** Unknown binding type → rejected-with-report, not vanished; version round-trip; typed op
kind survives queue restart; exporter includes the record.

---

## P3 — Cost-tracker accuracy (Plan AU riders) 🟠 Money

**The bugs.** Capture reads only `input_tokens`/`output_tokens` (`UsageTracker.swift:52-53`,
`StreamingUsageAccumulator.swift:19-21`) — Anthropic **cache** tokens
(`cache_creation_input_tokens`/`cache_read_input_tokens`) are invisible, and post-BF
`cache_control` history makes that the largest single error source. Longest-prefix pricing
(`ModelPricing.swift:64-71`) silently bills a future `claude-opus-4-9` at the `claude-opus-4`
family rate (3×) instead of nil-unknown. A renamed usage block is a designed no-op with no marker.

**Fix.** Parse cache fields on both non-streaming and SSE paths; per-row cache rates in
`ModelPricing` (write ≈1.25× input, read ≈0.1× — table-driven, not hardcoded); date-suffix-aware
prefix matching or freshness guard; an "untracked turns" marker on shape-drift; a pricing-table
note that realtime voice bills at audio rates (tokens right, dollars approximate).

**Tests.** Cache-inclusive cost math; dated-variant id → nil not family rate; drift counter
increments on an unrecognized usage shape.

---

## P4 — Health-check rubric false negatives (Plan AB riders) 🟠 Medical

**The bugs.** `.anticoagulated` is parsed from the vault (`SubstanceCatalog.swift:109`) but
`check()` never consults it — "on blood thinners" in conditions.md with no recognized drug name
misses the flagship high-severity NSAID hit (`InteractionRubric.swift:33` keys on drug class only).
`.asthma` is parsed but no rule uses it (NSAID + aspirin-exacerbated respiratory disease is
textbook curated-tier). `Substance.isClassified` is never used — an unrecognized brand name yields
the same authoritative "No high-severity interactions found" as a genuinely-checked substance.

**Fix.** Condition-tag branch on the NSAID/anticoagulant rule; the NSAID+asthma rule;
`!isClassified` → "I don't recognise X in my interaction table"; a `SystemPromptBuilder` rule that
health/medication-safety questions MUST route through `health_check` (in Direct mode the LLM can
currently answer from its own weights, no rubric/disclaimer). Disclaimer path untouched
(`compose()` appends unconditionally — preserve).

**Tests.** Extend the 14 HealthSafety tests: condition-only anticoagulation hits; asthma+NSAID
hits; unrecognized wording; prompt contains the routing rule.

---

## P5 — Small verified fixes 🟡 (one PR, mechanical)

- **`switch_harness` case mismatch:** schema enumerates `["openclaw","custom"]`
  (`AgentControlTool.swift:38`) and the lookup lowercases (`:84-85`), which can never match
  `codexCloud`/`claudeRemote` — voice-switching to the Phase 3 harnesses is impossible.
  Case-insensitive kind lookup + full schema enum + tests.
- **Custom-harness hygiene (Plan N):** `CustomHarnessConfig.isConfigured` accepts `http://` (token
  goes cleartext — require https or warn); percent-encode the server-controlled `{id}` template
  substitution (`CustomHarnessConfig.swift:52,68`).
- **Realtime resume owner check (Plan AP):** `resumeAfterInterruptionOnQueue` reactivates the
  session with no `currentOwner` check (`RealtimeAudioEngine.swift:414-416`) — a resume after a
  phone call can stomp whoever acquired the session meanwhile. Add the ledger check (mirror
  `WakeWordService.swift:297-301`). Prerequisite to any AP device validation.
- ✅ **Keyless Custom sends** — fixed 2026-07-10 on `feat/locale-aware-speech`
  (`LLMService.openAICompatibleAuthorization` + `OpenAICompatibleAuthTests`); test run pending the
  sim-runtime recovery.

---

## P6 — MCP catalog + trust follow-ups (Plan V riders) 🟡

- **Catalog custom auth-header kind** (`{"kind":"header","header":"X-API-Key"}`): new `MCPAuthKind`
  case + `makeServerConfig` branch + install-screen field. The transport already applies arbitrary
  headers; only the catalog can't express it. **Prerequisite for Plan BL P1's one-tap peer install.**
- **Launch-time re-discovery:** discovered MCP tools live in memory and vanish on relaunch until
  the user re-taps "Discover Tools" (`MCPServersView.swift:156-163`) — quietly breaking the
  catalog's promise, and making the Plan R definition screen point-in-time. Re-discover (and
  re-scan) on launch for installed servers.

**Tests.** Header-kind install round-trip produces the right header; relaunch path re-populates
tools and re-runs the scanner.

---

## P7 — Diarization visibility (Plan AQ's promoted item) 🟡

Speaker chips are never rendered: `CaptionEntry.speaker` is populated
(`AmbientCaptionService.swift:235-243`) but no view consumes it, while
`DiarizationSettingsView.swift:72` instructs "Tap a speaker chip on a caption to name them" — a UI
that doesn't exist. Small SwiftUI work in `AmbientCaptionOverlay`: chip per caption when a speaker
id is present, tap-to-name writing through `SpeakerRegistry`. Gates any live-WebSocket device
validation (no point validating an invisible feature). The on-device sherpa-onnx batch path stays
re-scoped in the AQ doc (bigger than a rider).

**Tests.** Chip renders when `speaker != nil`; naming round-trips the registry; no chip when
diarization off.

---

## P8 — Project-boundary leak: scope BrainTool/TeleprompterTool retrieval 🔴 Privacy

**The bug (verified — the boundary is violated in shipped code).** `BrainTool.swift:187` calls
`documentStore?.query(question, limit: 3)` with the default `namespace: nil`, and
`DocumentStore.fetchChunks` with nil namespace returns **all** namespaces
(`DocumentStore.swift:346-352`) — so `brain ask` in an unscoped/global chat retrieves and quotes
passages from every project's documents. `BrainTool.swift:180` does the same across persona-scoped
memory namespaces. `TeleprompterTool.swift:77` resolves `store.document(named:)` across all
namespaces — any chat can read any project's full document text by name. (`DocumentRAGTool` scopes
correctly — `DocumentRAGTool.swift:59,87` — and `StudyService` pins ids; the leak is these two.)

**Fix.** Thread the same `activeNamespace` closure `DocumentRAGTool` uses into `BrainTool`; memory
policy: nil → `["global", activePersonaId]`, never all. Decide `TeleprompterTool` (recommend:
active project + global). State the invariant Plan AN's open question missed: **global never sees
project docs** (the inverse of "projects see global").

**Tests.** Scoped doc invisible to an unscoped `brain ask`; visible inside its project; memory
search never crosses personas; teleprompter lookup honors the namespace.

## P9 — Chat SSE hardening (Plan AK riders) 🟠

**The bugs (verified).**
- **Silent truncation:** the Anthropic event switch (`LLMService.swift:1638-1663`) handles only
  content events; a mid-stream `{"type":"error"}` (e.g. `overloaded_error`) hits `default: break`
  and the **partial** content returns as a successful turn — persisted and appended to history.
  Same shape on the OpenAI path (mid-stream `error` line skipped by the `choices` guard; premature
  EOF before `[DONE]` = success).
- **Resilience asymmetry:** realtime voice has `RealtimeReconnect` (backoff + fatal-vs-recoverable,
  Plan BD); chat SSE is single-shot — a transient 429/529 throws straight to `errorMessage`.
- **Every tool-loop iteration streams** (`body["stream"] = true` whenever `onToken != nil`,
  `:1248`, per iteration) and AppState's accumulator never resets between iterations
  (`OpenGlassesApp.swift:2826`) — bubbles can show concatenated intermediate+final text until the
  persisted swap. The plan/comment claim "only the final turn streams" is false.

**Fix.** Inject the `URLSession` into both SSE helpers (they hardcode `.shared`, `:1556/:1615` —
the `MockURLProtocol` pattern from `MCPTransportTests.swift:66-91` is the precedent); handle
mid-stream `error` events as thrown errors (never return partials as success); reset the
accumulator per iteration (or stream final turn only, matching the documented intent); apply a
`RealtimeReconnect`-style retry policy to transient SSE failures. With the seam, the deferred
"needs real keys + device" verification becomes **headless fixture tests** (delta assembly,
tool_call accumulation, usage capture, `[DONE]`/EOF, the error cases); only a live-credential
smoke stays device-bound.

**Tests.** Fixture streams for both providers: happy path, mid-stream error → throw (no partial
persisted), premature EOF → throw, 429 retries then succeeds, accumulator resets per iteration.

## P10 — Owner gate on Settings + Simple-Mode exit 🟡

**The gap.** Simple Mode (shipped, `e5cdddc`) hides the owner Settings surface — but its exit is a
plain toggle (`SettingsView.swift:603-606`): anyone holding the phone flips it and regains
Settings, including API-key fields that render decrypted. Conversations already have a biometric
lock (`ConversationStore.isLocked`); Settings has none. This is the PIN half of AJ's deferred
"profiles+PIN," extracted: an owner gate (Face ID / device passcode via `LAContext`, PIN fallback)
on Simple-Mode exit and optionally on Settings entry. Full multi-profile storage stays deferred in
AJ pending a real shared-device commitment.

**Tests.** Gate state machine pure-tested (locked → auth → unlocked, failure paths); Simple-Mode
exit requires a grant.

---

## Sequencing

**P0 → P8 → P1 first** (bystander-audio privacy, then the live project-boundary leak, then data
loss). P2–P7, P9–P10 in any order after. P5's resume-owner-check lands before any AP/BJ on-glasses
smoke test; P6's header kind lands before BL PR1; P9 pairs naturally with the AU work in P3 (same
SSE code). Full suite + Release green before each PR per house style.
