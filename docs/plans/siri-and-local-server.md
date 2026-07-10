# Plan AF — Siri Conversational Intents + Self-Hosted Local Server Polish

**Status: 🚧 Mostly shipped.** Thread A (Siri persona intent + conversational follow-up +
snippet) shipped in PRs #93/#94. Thread B/C: **connection-test (#4) + local-server presets
(#5) shipped** — `ModelFetcher.testConnection` (pure `classify`) + a "Test Connection" button,
and `LocalServerPreset` (Ollama / LM Studio / vLLM / LocalAI) with a base-URL prefill picker in
`ModelFormView`. **#6 LAN auto-detect (mDNS): core landed** — pure `LocalServerDiscovery`
(`candidates(host:)` + `rewriteHost`, 5 tests) generates the per-preset probe URLs; live
`LocalServerScanner` (NWBrowser Bonjour `_http._tcp` browse → concurrent `ModelFetcher.testConnection`
probes) + an experimental "Scan local network" button in `ModelFormView` + `NSLocalNetworkUsageDescription`
/ `NSBonjourServices` Info.plist keys. The manual preset stays the primary path; live mDNS hit-rate
(many servers don't advertise Bonjour) is the device-pending edge.

**2026-07-10 review notes:**
- **Probe auth is keyless by construction — keep it that way.** Scan probes hardcode
  `apiKey: ""` (`LocalServerScanner.swift:39-40`) and `testConnection` only sets `Authorization`
  when the key is non-empty; the form's key goes only to the user-typed URL on an explicit Test
  tap. No bearer-token leakage to arbitrary LAN hosts exists; this line is here so a future edit
  doesn't introduce it.
- **Trust-on-discovery is the real unflagged risk.** Any LAN device can advertise `_http._tcp` and
  answer `GET /v1/models` with a plausible body (`modelCount(in:)` accepts any `data[]`/`models[]`
  array) — and a discovered server the user adopts then receives **all subsequent conversation
  content** (and any key typed into the form) over plain HTTP. Cheap mitigation: picker copy
  ("only connect to machines you recognise") + flag first-seen / non-`.local`-resolving hosts. Add
  regardless of the mDNS outcome, since the scanner ships behind the experimental button today.
- **#6's future is mesh-aware, not more Bonjour.** Plan BL makes the Tailscale mesh the default
  reachability posture; the interesting self-hosted LLM box is increasingly a tailnet peer that
  **mDNS multicast cannot discover** (it doesn't traverse the tailnet), while the manual path
  already handles tailnet hostnames. Verdict: validate live mDNS hit-rate once, cheaply, then
  apply this plan's own escape hatch ("cut this item if the hit-rate is poor"); any second
  iteration of discovery should be **tailnet-peer probing** (MagicDNS peer names through the same
  pure `LocalServerDiscovery.candidates` + `testConnection`), riding BL's infrastructure.

Builds on the Siri App-Intents layer and the keyless
Custom (OpenAI-compatible) provider already on
`claude/siri-meta-glasses-integration-g0q7xf`:

> **Already shipped on the branch:** a conversational, two-step `AskQuestionIntent`
> ("Hey Siri, ask OpenGlasses a question" → Siri prompts for and awaits the
> spoken question — App Shortcut phrases can't embed free-form `String`
> parameters) that routes the question through the existing `sendTextMessage`
> LLM/persona pipeline and has Siri speak the answer;
> `sendTextMessage(speakResponse:)` to avoid double TTS; a trimmed 10-shortcut
> `AppShortcutsProvider`; `Config.siriAskOpensApp` + a Settings toggle; and
> keyless self-hosted local-server support in `ModelFetcher` / `ModelFormView`
> (no API key required, ATS guidance for `.local`/Tailscale).

**Strategic fit:** Two threads that each extend work already in flight without
new architecture. The **Siri thread** makes the hands-free "Hey Siri" entry
point first-class (pick a persona, continue a conversation, see the answer in
the Siri card). The **local-server thread** turns the keyless Custom provider
into a guided setup (test the connection, prefill from presets, discover servers
on the LAN) — mirroring the value the `Potowai/local-meta-rayban-ai` fork added,
but on our real Wearables SDK pipeline and on-device stack.

**Effort:** ~3–4 days total. #1/#4/#5/#7 are small and high-value; #2/#3 are
medium; #6 (mDNS discovery) is the only piece with real platform risk.

---

## Scope (items 1–7)

| # | Item | Thread | Effort | Risk | Status |
|---|------|--------|--------|------|--------|
| 1 | Persona-targeted Siri intent | Siri | S | low | ✅ PR-2 |
| 2 | Conversational follow-up | Siri | M | low | ✅ PR-2 |
| 3 | Result snippet UI | Siri | S–M | low | ✅ PR-2 |
| 4 | Connection-test button ✅ | Local server | S | low | PR-3 (shipped) |
| 5 | Local-server presets ✅ | Local server | S | low | PR-3 (shipped) |
| 6 | LAN auto-detect (mDNS) — core ✅, live hit-rate pending | Local server | M–L | **medium** (platform) | PR-3 |
| 7 | Unit tests | Hardening | S | low | ✅ PR-1 (#93) |

---

## Thread A — Siri conversational intents

### 1. Persona-targeted Siri intent
*"Hey Siri, ask Claude on OpenGlasses what's on my calendar."*

Personas already are `{ wakePhrase, modelId, presetId, … }` in
`Config.savedPersonas`, and the app activates one with
`Config.setActiveModelId(persona.modelId)` (see `OpenGlassesApp.swift:1104`).

- New `PersonaEntity: AppEntity` + `PersonaQuery: EntityQuery` that enumerate
  enabled personas from `Config.savedPersonas`, so Siri/Shortcuts show the real
  persona list as a parameter.
- New `AskPersonaIntent` with `@Parameter var persona: PersonaEntity` and the
  same spoken `question` parameter as `AskQuestionIntent`.
- `perform()` resolves the persona, applies it the way the wake-word path does
  (set active model + persona prompt/soul context), calls
  `sendTextMessage(_, speakResponse: false)`, then **restores the previous
  active model** (mirror the save/restore at `OpenGlassesApp.swift:2557–2631`).
- Register one parameterized phrase. **Note the 10-shortcut cap** — adding this
  needs us to either drop another phrase or rely on the in-app Shortcuts/Siri
  parameter UI rather than a top-level `AppShortcut`. Decide at build time.

**Files:** new `Intents/AskPersonaIntent.swift` (+ `PersonaEntity`); small helper
on `AppState` to run a one-shot query under a temporary persona and restore.

### 2. Conversational follow-up
*A second "Hey Siri, ask OpenGlasses…" continues the same thread.*

`sendTextMessage` already reuses `conversationStore.activeThreadId` when
persistence is on, and `LLMService` keeps `conversationHistory`. The gap is
**intent**: the one-shot Siri call shouldn't implicitly start a fresh thread, and
a follow-up should land in the same thread within a time window.

- Add a `continueConversation` path: a `FollowUpIntent` (or a boolean parameter
  on `AskQuestionIntent`) that keeps `activeThreadId` instead of ending it.
- Add a short "recency window" so consecutive Siri asks reuse the active thread;
  outside the window, start fresh.
- Verify `LLMService.conversationHistory` is populated for Siri-initiated turns
  so the model actually sees prior context (wire `conversationStore` history into
  the request if it isn't already for this path).

**Files:** `Intents/AskQuestionIntent.swift`, `ConversationStore.swift`
(recency helper), `OpenGlassesApp.swift` (`sendTextMessage` thread handling).

### 3. Result snippet UI
*Show the answer (and any captured photo) in the Siri / Shortcuts card.*

- Give `AskQuestionIntent` / `AskPersonaIntent` / `QuickVisionIntent` a
  `SnippetView` via `.result(value:dialog:view:)` — a small SwiftUI view with
  the answer text and, for vision intents, the captured image.
- Keep the spoken `dialog` for the eyes-free case; the snippet is additive.

**Files:** new `Intents/IntentSnippets.swift` (shared SwiftUI snippet views);
update the three intents' return types.

---

## Thread B — Self-hosted local server

### 4. Connection-test button
*Validate the endpoint before saving — reachable? latency? auth?*

- Add `ModelFetcher.testConnection(provider:apiKey:baseURL:) async -> Result`
  returning an enum (`.ok(latencyMs, modelCount)`, `.unreachable`,
  `.httpError(code)`, `.ats` hint when a raw private IP likely tripped ATS).
- "Test Connection" button in `ModelFormView` (shown for `showBaseURL`
  providers) with a clear status line — turns "why doesn't it work" into a
  signal, and surfaces the `.local`/Tailscale-vs-raw-IP gotcha at setup time.

**Files:** `ModelFetcher.swift`, `ModelFormView.swift`.

### 5. Local-server presets
*Pick "Ollama / LM Studio / vLLM / LocalAI" → prefill base URL + port.*

- Small `LocalServerPreset` enum (display name, default base URL incl. port,
  default model hint, vision default).
- When provider is `.custom`, show a preset menu above the Base URL field that
  fills in `baseURL` / `model` (e.g. Ollama → `http://your-host.local:11434/v1`,
  `llava`). Editable afterward.

**Files:** new `Models/LocalServerPreset.swift` (pure), `ModelFormView.swift`.

### 6. LAN auto-detect (mDNS) — best-effort
*Scan the local network for a running server.*

- "Scan local network" button using `NWBrowser` over Bonjour, plus a fallback
  probe of `http://<bonjour-host>.local:<port>/api/tags` (Ollama) /
  `/v1/models` for discovered hosts.
- **Platform requirements (Info.plist):** `NSLocalNetworkUsageDescription`
  string and `NSBonjourServices` entries. Confirm/add these.
- **Risk:** Ollama/llama.cpp don't advertise Bonjour by default, so discovery is
  best-effort (probe common hostnames/ports). Ship behind clear "experimental"
  copy; the manual preset (#5) remains the primary path. Cut this item if the
  hit-rate is poor in testing.

**Files:** new `Services/LocalServerDiscovery.swift`, `ModelFormView.swift`,
`Info.plist`.

---

## Thread C

### 7. Unit tests
Mirror `OpenGlassesTests/ConfigTests.swift` (UserDefaults setup/teardown).
Refactor where needed so logic is pure and testable:

- ✅ **`Config.siriAskOpensApp`** — default `false`; set/get round-trip.
  (`SiriIntentSupportTests`)
- ✅ **`ModelConfig.inferredSupportsVision`** — `custom` + `llava`/`pixtral`/
  `minicpm-v` → true; bare text model → false; existing provider cases.
  (`ModelFetcherTests`)
- ✅ **`ModelFetcher` models-endpoint derivation** — extracted the URL-derivation
  in `fetchOpenAICompatible` into a pure `static func modelsEndpoint(from:)` and
  tested `/v1/chat/completions` → `/v1/models`, `/v1` → `/v1/models`, bare host →
  `/models` (+ trailing-slash and last-`/v1/`-wins edge cases). (`ModelFetcherTests`)
- ⏳ **Persona resolution helper (#1)** — name/phrase → persona match (pure).
  Deferred to PR-2 (lands with the persona intent it supports).
- ⏳ **`LocalServerPreset` (#5)** — preset → base URL/model mapping.
  Deferred to PR-3 (lands with the preset feature it supports).

**Files:** new `OpenGlassesTests/SiriIntentSupportTests.swift`,
`ModelFetcherTests.swift`; small pure-function refactors in `ModelFetcher.swift`.

---

## Suggested PR ordering (stacked)

1. ✅ **PR-1 (hardening):** the #7 tests + refactor for surfaces that exist today
   — `Config.siriAskOpensApp`, `ModelConfig.inferredSupportsVision`, and the
   extracted `ModelFetcher.modelsEndpoint(from:)` (13 tests). The persona/preset
   tests ride along with their features in PR-2/PR-3. Landed first to de-risk.
2. ✅ **PR-2 (Siri):** #1 `AskPersonaIntent` + `PersonaEntity`/`PersonaQuery`
   (`EntityStringQuery`; optional persona param so the generic ask still works;
   replaces the generic shortcut to stay under the 10-phrase cap); #2 thread-recency
   follow-up (`ConversationStore.continueRecentOrStartThread`); #3 `AnswerSnippetView`
   result card. `AppState.askUnderPersona` runs the turn under the persona's model
   then restores. Pure logic unit-tested; live Siri/persona routing is a hardware
   path, not device-verified.
3. **PR-3 (local server):** #4 connection test, #5 presets, then #6 discovery
   (separately, behind an experimental flag — droppable).

## Risks & decisions

- **10-shortcut cap** (#1): top-level `AppShortcut` slots are full. Either drop a
  phrase for the persona intent or expose it only via the Shortcuts-app
  parameter UI. Decide during PR-2.
- **`openAppWhenRun = false` + background** (all Siri intents): require
  `AppStateProvider.shared`; the `Config.siriAskOpensApp` toggle is the escape
  hatch when the app isn't resident.
- **mDNS discovery** (#6) is the only item that may not survive contact with real
  hardware; the manual preset path is the guaranteed experience.
- **Build verification:** none of this is compiler-checked in the web
  environment — generate the project locally (`./Scripts/generate-xcodeproj.sh`)
  and ⌘B before merging.
