# Plan — Memory, Recall & Self-Improvement (the closed learning loop)

**Status:** 📋 Planned (not built). The deterministic core (FTS index + query builder, nudge
heuristics, skill-pattern detector, insights aggregator) is fully headless-testable; only the
on-device summarization call is model-dependent — same posture as the rest of the brain work.
Native-first (the brain works without OpenClaw — see `[[project_brain_store]]`).

Three features built around a self-improving "closed learning loop," all reinforcing
OpenGlasses' on-device brain rather than the gateway. They share one substrate
(`ConversationStore` + `BrainStore` + a new conversation index), so they're phased as one
effort:

1. **Cross-session recall** — search and summarize your own past conversations.
2. **Self-improving memory loop** — proactive "remember this?" nudges + autonomous skill
   *suggestions*.
3. **Usage & insights** — a private, on-device recap of how you actually use the assistant.

## What we enable
- **Recall:** *"What did we decide about the museum app last week?"* / *"Summarize
  yesterday's conversations."* Full-text search over conversation history + an on-device
  summary, cited to the threads it came from.
- **Nudges:** after a rich turn (new durable fact, a repeated detail), a gentle *"Want me to
  remember that?"* → `BrainStore.ingest`. Off by default; presence-aware.
- **Skill suggestions:** when you repeat a multi-step request, *"Save this as a skill called
  'morning brief'?"* → a `voice_skill`. Today `voice_skills` is manual-only.
- **Insights:** a Settings recap — top topics, most-used tools, a weekly summary — computed
  **on-device**, no network.

## How the user interacts
1. **Recall** rides on the existing `brain` tool (new `recall` action) and voice: ask about
   the past, hear a cited summary.
2. **Nudges/suggestions** surface through `ProactiveAlertService` (the existing proactive
   channel), each a one-tap confirm; both behind their own Settings toggles.
3. **Insights** is a Settings view (and a `whats_my_usage`-style ask), updated periodically.

## Architecture — the seam
A `ConversationIndex` (SQLite **FTS5**, same `SQLite3` approach as the RAG `DocumentStore`)
indexes `ConversationStore` turns as they're saved. A `RecallService` runs a query →
top-k turns → on-device summarization (`LocalLLMService` when foreground, cloud `LLMService`
fallback when backgrounded, per `[[project_local_model_background]]`). The self-improving loop
is a set of **pure analyzers** fed by completed turns; their suggestions are routed through the
existing `ProactiveAlertService`. Insights is a pure aggregator over the index + `BrainStore`.

```swift
@MainActor final class RecallService: ObservableObject {
    func index(_ turn: ConversationTurn)                       // incremental FTS upsert
    func search(_ query: String, limit: Int) -> [RecallHit]    // pure-ish (FTS)
    func recall(_ query: String) async -> RecallAnswer         // search + summarize + cite
}
```

## Model (SDK-free, the deterministic core)
- `RecallHit` / `RecallAnswer` — typed search results + a cited summary. Pure values.
- `FTSQueryBuilder` — natural phrase → safe FTS5 MATCH (quoting, prefix, date filters like
  "yesterday"/"last week" → time range). Pure → tested.
- `MemoryNudgeAnalyzer` — completed turn → optional nudge (`{kind: .fact|.skill, payload}`).
  Heuristics only (durable-fact patterns; repeated multi-step request detection via a rolling
  command-shape history). Pure → tested; **no autonomous action**, only a suggestion.
- `SkillPatternDetector` — recognizes a repeated multi-tool sequence worth saving as a
  `voice_skill`. Pure → tested.
- `InsightsAggregator` — turns/tools/topics over a window → an `InsightsReport`. Pure → tested.

## Flow
```
ConversationStore.save(turn) ─► RecallService.index(turn)  [FTS5]
ask "what did we decide…?" ─► FTSQueryBuilder → ConversationIndex.search
                            ─► top-k turns → on-device summarize → cited RecallAnswer
turn completes ─► MemoryNudgeAnalyzer / SkillPatternDetector (pure)
              ─► (if enabled & user present) ProactiveAlertService → one-tap confirm
                 → BrainStore.ingest(...)  |  VoiceSkillStore.save(...)
Settings/ask ─► InsightsAggregator(index + BrainStore) → InsightsReport (on-device)
```

## Files
New (`OpenGlasses/Sources/Services/Memory/`):
- `ConversationIndex.swift` — FTS5 index over conversation turns (SQLite3).
- `RecallService.swift` — search + on-device summarize + cite.
- `RecallModels.swift` — `RecallHit`, `RecallAnswer`, `FTSQueryBuilder` (pure).
- `MemoryNudgeAnalyzer.swift` / `SkillPatternDetector.swift` — pure analyzers.
- `InsightsAggregator.swift` + `InsightsReport` — pure.

Touch:
- `ConversationStore.swift` — emit each saved turn to `RecallService.index`; backfill on first run.
- `NativeTools/BrainTool` (the `brain` tool) — add a `recall` action (or a thin `recall` tool).
- `NativeTools/VoiceSkillsTool.swift` — accept an analyzer-proposed skill (confirm → save).
- `ProactiveAlertService.swift` — a memory/skill suggestion channel (presence-aware, Plan W).
- `Views/SettingsView.swift` (+ `InsightsView`, `MemorySettingsView`) — insights + toggles.
- `Config.swift` — `recallEnabled`, `memoryNudgesEnabled` (default off), `insightsEnabled`.

## Build order (shared core first; recall the headline)
1. **Pure core + index** — `ConversationIndex` (FTS5) + `FTSQueryBuilder` + backfill, plus the
   pure analyzers/aggregator, exhaustively tested (no model, no UI).
2. **Recall** — `RecallService` (search + on-device summarize + citations); `brain` `recall`
   action + voice. (Summarization is model-dependent; the search/index is proven in 1.)
3. **Self-improving loop** — wire `MemoryNudgeAnalyzer` + `SkillPatternDetector` into
   `ProactiveAlertService`; one-tap confirm → `BrainStore.ingest` / `voice_skill`. Toggles off
   by default; respect presence.
4. **Insights** — `InsightsAggregator` → `InsightsView` + a spoken recap.

## Tests
- `FTSQueryBuilder`: phrase quoting; FTS injection-safe MATCH; "yesterday"/"last week" → range.
- `ConversationIndex`: upsert/dedup; search ranking; backfill idempotence (temp DB).
- `MemoryNudgeAnalyzer`: durable-fact fires; small-talk doesn't; **no double-nudge** on repeats.
- `SkillPatternDetector`: repeated multi-step sequence → suggestion; one-off doesn't.
- `InsightsAggregator`: top topics/tools counts; window boundaries; empty history.
- Privacy: nudges/insights produce nothing when their toggle is off.

## Open questions / decisions needed
- **Summarization model** — `LocalLLMService` (MLX, private, foreground-only) vs the configured
  cloud LLM when backgrounded; pick per `[[project_local_model_background]]`. Default to local
  when available.
- **Privacy** — recall and insights run **on-device**; never send conversation history to a
  cloud LLM unless the user's chosen provider already is the summarizer (disclose it). **HIPAA
  mode** excludes clinical threads from recall/insights or requires explicit consent.
- **Gating** — own Settings toggles, **not** `agentModeEnabled`. *Suggestions* (propose →
  user confirms) are safe without agent mode; any **auto-action** (saving without confirm)
  stays behind `agentModeEnabled` (see `[[feedback_agentic_toggle]]`).
- **Nudge cadence** — presence-aware (no nudges when away/disengaged, Plan W); rate-limited so
  it never feels naggy. Default off; opt-in.
- **Index size** — cap/rotate the FTS index; decide retention (e.g. mirror `ConversationStore`).
- **Brain overlap** — recall indexes *raw conversation turns* (new); `BrainStore` keeps holding
  *curated* facts/summaries. Keep them distinct; recall can promote a hit into the brain.

## Dependencies / prereqs
- Existing: `ConversationStore`, `BrainStore` (`ingest`), the `brain` tool, `VoiceSkillsTool`,
  `ProactiveAlertService`, `PresenceMonitor` (Plan W), `LocalLLMService` + `LLMService`,
  the SQLite3/FTS approach from `RAG/DocumentStore`. **No new SPM dependency** (SQLite is
  system; summarization reuses existing LLM services).

## Why this matters
A memory-first assistant that can't search its own memory is half-built. Recall turns every
past conversation into something you can ask about hands-free; the self-improving loop means
the brain *grows* without the user having to curate it by hand; insights make that growth
legible. All three deepen the on-device brain (native-first, private) rather than leaning on
the gateway — and the hard parts (FTS query building, nudge/skill heuristics, aggregation) are
pure, fully-testable functions over data structures already in the app. The closed-learning-loop
shape (agent-curated memory, autonomous skill creation, cross-session recall) is well-proven;
the code here is written fresh in Swift.
