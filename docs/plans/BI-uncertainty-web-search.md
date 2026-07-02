# Plan BI — Uncertainty-Triggered Web Search (local backends)

**Status:** 📋 Planned.

## Why this shape

Cloud providers (Anthropic, Gemini, OpenAI, xAI) resolve questions they don't know the answer to
by **calling `web_search`** through the normal tool loop. The two **local backends do not tool-call
reliably**:

- **On-device MLX** — `sendLocal(...)` in [LLMService.swift](../../OpenGlasses/Sources/Services/LLMService.swift)
  routes to `LocalLLMService.generate(...) -> String`, a plain completion. It parses an optional
  `<tool_call>` marker, but the local prompt tells the model to use tools "sparingly" and only ~12
  simple tools are offered — `web_search` is **not** among them, so it's unreachable from a local turn.
- **Apple Foundation Models** — `sendAppleOnDeviceImpl(...)` calls `LanguageModelSession.respond(to:)`
  and returns `response.content`. No tool channel wired; the small on-device model answers stale /
  "I'm not sure" questions from its own weights.

The result: on a local backend the user gets a confident-sounding wrong answer (or a flat "I don't
know") for anything time-sensitive — prices, scores, "who won", "what's the latest" — even though we
ship a perfectly good `WebSearchTool` (Perplexity → DuckDuckGo). This plan adds a **deterministic
uncertainty gate** that detects a low-confidence / needs-fresh-data local answer and transparently
re-answers it with a web-search result.

Local-backend-only. Cloud tool-calling is unchanged. Foreground-only by construction — inherits the
existing "MLX can't run backgrounded" guard in `LocalLLMService` (there are no background local turns
for the gate to fire on).

## Core (this PR — deterministic, headless-testable)

Two pure types + a Config flag + two thin call-site hooks. No new service, no new UI, no new network
surface (reuses `WebSearchTool` as-is).

### New pure files

- **`Services/LLM/UncertaintyDetector.swift`** — `assess(question:answer:) -> UncertaintyVerdict`
  where `UncertaintyVerdict { shouldSearch: Bool; reason: UncertaintyReason? }` and
  `UncertaintyReason { case hedged, freshnessRequested }`. Two independent signals, either trips the
  gate:
  1. **Answer hedging** — the completion matches curated epistemic hedges ("i'm not sure",
     "i don't have access", "as of my last update", "my training data", "i cannot browse",
     "i don't have real-time"). Normalized, anchored to epistemic phrasing — **not** a bare
     `contains("not sure")` that would fire on "not sure if you'd like…" politeness.
  2. **Question freshness** — the *question* asks for volatile data ("today", "latest", "current",
     "right now", "this week", "who won", "score", "price of", "how much is"). Fires even when the
     answer sounds confident, because a confident stale answer is the worst case. Freshness wins the
     reported `reason` when both trip.
- **`Services/LLM/UncertaintyReask.swift`** — `answer(question:originalAnswer:search:regenerate:)`,
  pure orchestration over injected closures. Runs `search(question)`; empty/nil/throw → return
  `originalAnswer` (never worse than today). Otherwise splices the results into a grounding preamble
  and calls `regenerate` **exactly once** (no loops, bounded latency); regenerate throws → fall back
  to `originalAnswer`. Prepends a short transparency prefix ("Checked the web for that — ") so the
  answer is never silently swapped — consistent with the project's no-silent-fallback stance.

### Wiring (`LLMService.swift`, two call sites)

- **`sendLocal`** — after the no-tool-call `cleanResponse` is computed (the final `return cleanResponse`
  branch), route through the gate before appending to history/returning. `search` =
  `WebSearchTool().execute(args: ["query": text])`; `regenerate` = `localService.generate(...)` with
  the grounding spliced into `fullPrompt`.
- **`sendAppleOnDeviceImpl`** — same gate on `response.content` before returning; `regenerate` =
  `appleSession!.respond(to:)`.
- Both guarded by `Config.localWebSearchFallbackEnabled && Config.isWebSearchConfigured` — a no-op when
  the flag is off or no search backend is configured (mirror `WebSearchTool`'s own availability check).

### Config

- **`localWebSearchFallbackEnabled: Bool`** in `Utils/Config.swift`, default **on**, using the existing
  `object(forKey:) == nil ? true : bool(forKey:)` default-true pattern already used for triggers.

### Tests (headless, `OpenGlassesTests/`)
- `UncertaintyDetectorTests`: hedged answers trip; polite non-epistemic "not sure if you'd like" does
  **not**; fresh-data questions trip regardless of answer confidence; evergreen question + confident
  answer does not; flag off → detector never consulted.
- `UncertaintyReaskTests`: happy path prefixes + regenerates once (spy asserts exactly one regenerate
  call); empty/failed search → original answer returned; regenerate throws → original answer.

## Deferred / follow-ups

- **Confidence via logits/perplexity** rather than string signals — MLX exposes token probabilities;
  a low-max-prob / high-perplexity completion is a stronger uncertainty signal than phrase matching.
  Model-specific and larger; the string classifier is the deterministic first cut and stays as the
  cheap always-available fallback.
- **Apple Foundation guided-tool path** — if/when the on-device model gains reliable tool-calling,
  prefer a real `web_search` tool call over the re-ask splice on that backend; the detector becomes a
  belt-and-braces backstop.
- **Extend to cloud "no-tool" turns** — the same gate could catch a cloud model that answered stale
  without calling `web_search`, but cloud tool-calls well, so low value and out of scope.

## Notes

- Reuses `WebSearchTool` (Perplexity → DuckDuckGo) — no new keys or network surface.
- Foreground-only; inherits the existing background-inference guard — the gate never fires on a
  background local turn.
