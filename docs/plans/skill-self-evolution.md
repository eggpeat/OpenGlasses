# Plan — Skill Self-Evolution (learn new skills from failed turns, with human review)

**Status:** 📋 Planned (not built). The largest of these four plans and the most
safety-sensitive. **Agent-Mode-gated** and **human-in-the-loop by design** — the loop *proposes*
skills, the user *approves* them; nothing self-authored is injected into the always-on assistant
unreviewed. The trigger, dedup, and proposal-validation are pure and headless-testable; the LLM
analysis + review UI are the live edge. No new SPM dependency.

## The problem
OpenGlasses' skills are **static**: `InstalledSkillStore`, `VoiceSkillStore`, OpenClaw skills, and the
`ShortcutsCatalog` are all hand-curated and injected into prompts as-is. When the agent repeatedly
fumbles the same kind of task — a tool it keeps calling wrong, a phrasing the user keeps correcting,
a workflow it forgets — there's no mechanism to **learn** from those failures. The knowledge to fix
it exists in the transcript; nothing harvests it.

## What we build
A closed-but-supervised improvement loop:
1. **Capture** unsatisfactory turns as `FailureSample`s — a tool call that errored, an explicit user
   correction ("no, that's wrong" / "I meant…"), a retried/abandoned request.
2. **Trigger** evolution when enough accumulate (batch size **or** failure rate over a window).
3. **Analyse** the batch with one LLM call that proposes a small, named **skill** — a `SKILL.md`-style
   instruction ("when the user asks X, do Y; avoid Z") addressing the recurring failure.
4. **Dedup** the proposal against existing skills (name overlap + token similarity) so we don't pile
   up near-duplicates.
5. **Review** — surface the proposal in a "Suggested Skills" inbox. The user **approves** (→ added to
   `InstalledSkillStore`, injected like any installed skill) or **dismisses** (recorded so it isn't
   re-proposed). Never auto-applied.

### The deterministic core (pure, tested)
- **`FailureSample`** — `{ kind, prompt, response, toolName?, userCorrection?, at }`. `kind` ∈
  `{toolError, userCorrection, retry, abandoned}`.
- **`EvolutionTrigger`** — `shouldEvolve(samples, now) -> Bool`: true when `count ≥ batchThreshold`
  **or** `failureRate(window) ≥ rateThreshold`. Pure; time injected.
- **`SkillDeduplicator`** — `isDuplicate(candidate, existing) -> Bool` via name-token **Jaccard** +
  body token-overlap above a threshold. Pure.
- **`SkillProposal`** — parse + **validate** the LLM's output: slug rules (`^[a-z][a-z0-9-]+$`),
  required fields, length caps, auto-name `dyn-NNN` when unnamed. Reject malformed proposals (never
  surface garbage for review). Pure.

## Safety posture (non-negotiable)
- **Agent-Mode-gated** — the whole feature is behind `agentModeEnabled`; off by default, like every
  other autonomous/gateway capability.
- **Human-in-the-loop** — proposals are *suggestions*. A self-authored instruction only ever enters
  the prompt after explicit user approval. This is the key divergence from a fully-autonomous evolver:
  an always-on assistant must not silently rewrite its own behaviour.
- **Screened** — an approved skill is still routed through the existing prompt-injection / tool-poison
  screens (Plan R) before it can take effect, exactly like an imported skill.
- **Reversible** — approved evolved skills are tagged `source: evolved`, listed separately, and
  one-tap removable; dismissals are remembered.

## Scope
In:
- `Sources/Services/Skills/FailureSample.swift`, `EvolutionTrigger.swift`, `SkillDeduplicator.swift`,
  `SkillProposal.swift` (pure core).
- `Sources/Services/Skills/SkillEvolutionService.swift` — collect samples from the agent loop, run the
  trigger, make the LLM call, dedup, enqueue proposals for review. Agent-Mode-gated.
- `Sources/Services/Skills/EvolvedSkillStore.swift` — pending proposals + approved/dismissed state
  (SQLite), feeding `InstalledSkillStore` on approval.
- Capture hooks: `AgentRunner` / `NativeToolRouter` (tool errors) and `AppState` (user corrections /
  retries) emit `FailureSample`s.
- A "Suggested Skills" review surface (Settings) — approve / edit / dismiss.

Out (deferred):
- Fully-autonomous apply (no review) — explicitly **not** building; review is the safety boundary.
- Evolving *tool definitions* or code — proposals are prompt-level instructions only.
- Cross-device sync of evolved skills — local first; rides the existing skills export/import later.
- RL-style scoring/reward of skills — start with explicit user approve/dismiss as the signal.

## Architecture — the seam
```swift
struct FailureSample { enum Kind { case toolError, userCorrection, retry, abandoned }
    let kind: Kind; let prompt: String; let response: String
    let toolName: String?; let userCorrection: String?; let at: Date }

enum EvolutionTrigger {
    static func shouldEvolve(_ samples: [FailureSample], now: Date,
                             batchThreshold: Int, rateThreshold: Double, window: TimeInterval) -> Bool
}
enum SkillDeduplicator { static func isDuplicate(_ candidate: SkillDraft, against existing: [SkillDraft]) -> Bool }
enum SkillProposal { static func validate(_ raw: String, existingNames: Set<String>) -> SkillDraft? }  // nil = reject
```
`SkillEvolutionService` orchestrates these and is the only piece that calls the LLM or touches stores;
the decisions that matter (when to evolve, is it a dup, is it well-formed) are pure and tested.

## Build order
1. **Pure core + tests** — `EvolutionTrigger`, `SkillDeduplicator`, `SkillProposal`. Fully
   deterministic; no LLM, no store.
2. **`EvolvedSkillStore`** — pending/approved/dismissed persistence + round-trip tests.
3. **Capture hooks** — emit `FailureSample`s from tool errors + user corrections (cheap, additive,
   Agent-Mode-gated).
4. **`SkillEvolutionService`** — wire trigger → LLM analysis → dedup → enqueue. (LLM edge.)
5. **Review UI** — Suggested Skills inbox; approval routes through the Plan R screen into
   `InstalledSkillStore` tagged `evolved`.

## Tests
- `EvolutionTrigger`: under threshold and low rate → false; batch threshold reached → true; high
  failure rate in-window → true; old samples outside the window don't count. Time injected.
- `SkillDeduplicator`: identical/near-identical name+body → duplicate; distinct → not; threshold
  boundaries.
- `SkillProposal.validate`: valid slug + fields → draft; bad slug / missing field / over-length →
  nil; unnamed → auto `dyn-NNN` not colliding with `existingNames`.

## Open questions / decisions needed
- **What counts as a failure** — start conservative (explicit tool errors + explicit user
  corrections); add "retry/abandoned" heuristics only once the signal proves clean (false positives
  pollute the skill bank).
- **Review friction vs. value** — a proposal the user must read is the safety cost; keep proposals
  short, few, and high-confidence (dedup hard, require a real recurring pattern) so the inbox is rare
  and worth opening.
- **Which model analyses** — reuse the active provider, or pin a stronger model for the analysis step
  (it's infrequent). Surfaces in the [cost tracker](llm-cost-usage-tracker.md).
- **Edit-on-approve** — let the user tweak the wording before accepting; treat the LLM output as a
  draft, not a verdict.

## Why this matters
It's the one genuinely *self-improving* capability in the set: the assistant gets better at the things
*this* user keeps needing, by harvesting fixes that are already sitting in the transcript. The risk —
an always-on agent rewriting its own instructions — is contained by making the loop **propose, not
apply**, gating it behind Agent Mode, and running approvals through the existing safety screen. The
hard logic (when to evolve, dedup, validate) lands as a pure, fully-tested core; the LLM and the
review inbox are the deferred live edge.
