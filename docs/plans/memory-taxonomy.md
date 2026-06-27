# Plan — Typed Memory Taxonomy (episodic / semantic / preference / project recall)

**Status:** 📋 Planned (not built). A typed layer over the existing on-device memory stores that adds
the two memory kinds we don't model today — **preferences** and **project state** — and a
*differentiated* recall policy so the right kind of memory reaches the prompt for the right reason.
The classifier, the retrieval policy, and the store round-trip are pure and headless-testable;
embedding similarity rides the existing `Embedder`. **Zero LLM calls** (pattern-based classification,
mirroring `BrainRelationExtractor`'s precision-over-recall posture). No new SPM dependency. Strictly
on-device, never synced to the gateway — same posture as `BrainStore`.

## The problem
OpenGlasses already has three memory substrates, but each answers only one shape of question:
- **`BrainStore`** (`brain.sqlite`) — a relational graph: entities, typed edges ("Alice works_at
  Acme"), person **encounters**, and follow-up **needs**. Great for "who works at Acme?".
- **`SemanticMemoryStore`** — flat facts retrieved by vector similarity ("what facts resemble this?").
- **`DocumentStore`** — passages from loaded files.

What none of them models is the **kind** of a memory, and two kinds in particular are simply absent:
- **Preferences** — "I prefer metric units", "always read me the urgent line first", "I take my
  coffee black". Durable, low-volume, and they should bias *every* turn — but today they'd land as an
  undifferentiated fact (if at all) and only surface when a query happens to resemble them.
- **Project state** — "I'm mid-way through the walk-in cooler job at Site 7; compressor swap is next".
  Ongoing, scoped to an active context, and should clear/yield when the user switches projects.

Without a kind dimension, recall is one-size-fits-all: everything competes in the same vector top-k.
Preferences get out-ranked by a topically-closer fact; project state isn't pinned while a job is
active; episodic events ("what did I do this morning") aren't retrievable by recency. The fix isn't a
bigger model — it's **typing** the memory and recalling each kind on its own terms.

## What we build
A typed memory record with a deterministic classifier, a differentiated retrieval policy, and a
formatter that assembles the per-turn memory block:

1. **Classify** incoming text (the same text `BrainStore.ingest` already sees) into one of four kinds —
   `preference`, `project`, `episodic`, `semantic` — by pattern, no LLM.
2. **Store** it as a typed `MemoryRecord` with salience + timestamps, alongside (not replacing) the
   graph edges the brain already extracts.
3. **Recall** per-kind when building the prompt: **always** inject preferences (capped), inject the
   **active project's** state, inject the top-k **semantic** facts by embedding similarity to the
   turn, and the most **recent episodic** events — each with its own budget.
4. **Decay/scope**: episodic ages out; preferences persist; project state is scoped to a project tag
   and yields when the active project changes.

### The deterministic core (pure, tested)
- **`MemoryRecord`** — `{ id, kind, text, subject?, projectTag?, salience, createdAt, lastAccessedAt }`.
  `kind ∈ {preference, project, episodic, semantic}`. Pure value type.
- **`MemoryClassifier`** — `classify(_ text:) -> MemoryKind` by cue patterns:
  - *preference*: first-person durable cues — "I prefer/like/want/always/never/usually", "call me…",
    "use … units".
  - *project*: progress/state cues tied to work — "working on", "mid-way", "next step is", "still need
    to", "on the … job", an active `FieldSessionService` job in scope.
  - *episodic*: a past event with a time/place — past-tense + temporal marker ("this morning",
    "yesterday", "at the…"), or a logged encounter.
  - *semantic*: the default (a durable fact) when nothing else fires.
  Precision over recall: an unclear line falls to `semantic` (the safe, already-handled bucket).
- **`MemoryRetrievalPolicy`** — pure ranking. Given `(query, candidates, similarity, budgets, now,
  activeProject)` returns the selected records: all `preference` up to `maxPreferences`; `project`
  records for `activeProject`; top-`k` `semantic` by injected cosine similarity; most-recent
  `episodic` within a recency window. Stable ordering; time + similarity injected so it's
  deterministic.
- **`MemoryContextBuilder`** — pure formatter: selected records → a `# What I remember` block with
  per-kind subheadings (`Preferences`, `Current project`, `Relevant facts`, `Recently`). Empty input
  → "".

## How it flows (live edge)
1. `BrainStore.ingest(text:)` already runs on new memory text. A parallel call hands the **same text**
   to `MemoryClassifier` → a `MemoryRecord` is stored in `TypedMemoryStore`. (The graph edges and the
   typed record are complementary, not either/or.)
2. When `LLMService` assembles the system prompt, a new `TypedMemoryStore.promptContext(for: turn)`
   runs `MemoryRetrievalPolicy` over the candidates (embedding the turn via `Embedder`) and
   `MemoryContextBuilder` formats the result — injected alongside the existing social/vault/skill
   blocks.
3. `lastAccessedAt` is bumped on inject so a salience/decay pass can favour what actually gets used.
4. Active project comes from `FieldSessionService` (a job session) or an explicit "I'm working on X"
   classified as `project`; switching projects scopes which `project` records are eligible.

## Scope
In:
- `Sources/Services/Brain/MemoryRecord.swift`, `MemoryClassifier.swift`, `MemoryRetrievalPolicy.swift`,
  `MemoryContextBuilder.swift` (pure core).
- `Sources/Services/Brain/TypedMemoryStore.swift` — SQLite persistence (a `memory_records` table; reuse
  `brain.sqlite` so it stays one on-device, un-synced DB), `add`, `records(kind:)`,
  `promptContext(for:)`, salience bump, decay sweep.
- `BrainStore.ingest` — add the parallel classify-and-store call (cheap, additive).
- `LLMService` system-prompt builder — inject the typed-memory block (behind a flag; default off
  reproduces today's behaviour exactly).
- `Config` — `typedMemoryEnabled` (default off), `memoryMaxPreferences`, `memorySemanticTopK`,
  `memoryEpisodicWindow`.

Out (deferred):
- An LLM-based classifier or summariser — start pattern-based; the heuristic is the testable core, and
  an LLM pass can refine kinds later if the signal warrants it (surfaces in the
  [cost tracker](llm-cost-usage-tracker.md)).
- Cross-device sync of typed memory — local-first, like the brain; rides the existing export/import
  later.
- Migrating `SemanticMemoryStore`'s existing flat facts into typed records — new memories are typed
  going forward; a back-fill is a separate follow-up.
- A user-facing memory editor (review/forget by kind) — read path first; a "Memory" surface in
  Settings is a fast follow once the kinds prove useful.

## Architecture — the seam
```swift
enum MemoryKind: String, Codable { case preference, project, episodic, semantic }

struct MemoryRecord: Identifiable, Equatable {
    let id: UUID
    let kind: MemoryKind
    let text: String
    let subject: String?        // person/org the memory is about, if any
    let projectTag: String?     // scopes `project` records to an active job
    let salience: Double
    let createdAt: Date
    var lastAccessedAt: Date
}

enum MemoryClassifier {                                   // pure; zero LLM
    static func classify(_ text: String) -> MemoryKind    // defaults to .semantic
}

enum MemoryRetrievalPolicy {                              // pure; similarity + now injected
    static func select(query: String,
                       candidates: [MemoryRecord],
                       similarity: (String) -> Float,     // turn↔record cosine, via Embedder
                       activeProject: String?,
                       now: Date,
                       maxPreferences: Int, semanticTopK: Int, episodicWindow: TimeInterval)
        -> [MemoryRecord]
}

enum MemoryContextBuilder {                               // pure formatter
    static func block(_ records: [MemoryRecord], now: Date) -> String   // "# What I remember…"
}
```
`TypedMemoryStore` owns the SQLite table and is the only piece that touches I/O or the `Embedder`; the
decisions that matter — what kind a memory is, which records to recall, how to present them — are pure
and fully tested. With `typedMemoryEnabled == false`, the prompt is assembled exactly as today.

## Build order
1. **Pure core + tests** — `MemoryClassifier`, `MemoryRetrievalPolicy`, `MemoryContextBuilder`. Fully
   deterministic; no store, no embedding model.
2. **`TypedMemoryStore`** — `memory_records` table in `brain.sqlite` + round-trip / query-by-kind /
   decay-sweep tests.
3. **Ingest hook** — classify-and-store alongside `BrainStore.ingest` (additive, cheap).
4. **Prompt injection** — `promptContext(for:)` wired into `LLMService` behind `typedMemoryEnabled`;
   embedding the turn via the existing `Embedder`.
5. **(Fast follow)** salience/decay tuning + an optional Settings "Memory" review surface.

## Tests
- `MemoryClassifier`: preference cues → `.preference`; project/progress cues → `.project`;
  past-tense + temporal marker → `.episodic`; an ordinary fact → `.semantic`; ambiguous → `.semantic`
  (never a confident wrong kind).
- `MemoryRetrievalPolicy.select`: all preferences included up to the cap; only the active project's
  `project` records pass; semantic results are the top-k by injected similarity; episodic respects the
  recency window and drops older; stable ordering; empty candidates → empty.
- `MemoryContextBuilder.block`: empty → ""; per-kind subheadings appear only when that kind has
  records; relative "Recently" labels computed from injected `now`.
- `TypedMemoryStore`: add/query-by-kind round-trips; `lastAccessedAt` bumps on recall; decay sweep
  drops aged episodic but never preferences; project scoping.

## Open questions / decisions needed
- **Reuse vs. new store** — put `memory_records` in `brain.sqlite` (one un-synced on-device DB, my
  default) or alongside `SemanticMemoryStore`? Reusing the brain DB keeps the "never synced to the
  gateway" guarantee in one place.
- **Classifier reach** — how aggressive the preference/project cues should be. Start narrow
  (high-precision first-person cues) so the always-injected `preference` bucket can't fill with noise;
  widen only once the signal proves clean, exactly as `BrainRelationExtractor` was tuned.
- **Budget split** — how many of each kind to inject before the block competes with the rest of the
  system prompt. Preferences are few and cheap to always include; semantic top-k and episodic window
  are the tunable knobs.
- **Active-project source** — derive solely from `FieldSessionService`, or also from an explicit
  "I'm working on X" the classifier tags `project`? Probably both, with the session taking precedence.
- **Decay curve** — does episodic age purely by time, or by time × inverse-access? Keep it simple
  (time window) first; add access-weighting only if recall feels stale.

## Why this matters
It closes the one real gap surfaced by surveying adjacent agent-memory work: the assistant has a graph
and a vector index but **no typed long-term memory** — so it can't reliably remember *how you like
things done* or *what you're in the middle of*. Typing the memory and recalling each kind on its own
terms (preferences always, project while active, semantic by relevance, episodic by recency) is what
turns "facts that happen to match" into memory that behaves the way a person's would. The hard parts —
classification, differentiated recall, presentation — land as a pure, fully-tested core with zero LLM
calls; the only live edge is wiring the block into the prompt behind a default-off flag. Pairs
naturally with [Visual State Memory](visual-state-memory.md) (its aged keyframe descriptions become
`episodic` records) and the [Embedding Quality Upgrade](embedding-quality-upgrade.md) (sharper
semantic recall through the same `Embedder` seam).
