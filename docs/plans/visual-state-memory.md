# Plan — Visual State Memory (rolling keyframe scene memory for the live agent)

**Status:** 📋 Planned (not built). Builds on [Content-Aware Frame Gate](frame-dedup-change-gate.md)
(its distinct frames are the keyframe source). The buffer + context-builder are pure and
headless-testable; per-keyframe description and prompt injection are the live edge. No new SPM
dependency.

## The problem
OpenGlasses' live vision is **stateless per frame**. Gemini Live sees the current throttled frame and
nothing about what came just before — so the agent can't answer "what was I *just* looking at?",
can't notice that a scene changed, and re-derives context from scratch every turn. We have a rich
*audio* continuity story (`MemoryRewindService` rolling buffer, `AmbientCaptionService` transcript)
but **no visual continuity track**. The glasses are a camera first; the agent should remember what it
saw.

## What we build
A short, rolling **visual state memory**: a per-session ring buffer of *keyframes* — only the
visually-distinct frames (from the change gate), each with a one-line description and a timestamp —
plus a builder that turns the last few into a compact **"Recent Visual Context"** block injected into
the live agent's prompt. The agent gains temporal scene awareness ("a kitchen 30 s ago → now a
laptop") without us re-sending every frame.

### The deterministic core
- **`Keyframe`** — `{ id, capturedAt, description, thumbnailRef }` (the image is referenced, not
  inlined, so the buffer stays light).
- **`VisualStateMemory`** — a fixed-capacity ring buffer (`maxKeyframes`), session-scoped, evicting
  oldest. Pure data structure: `add`, `recent(n)`, `latestDescription`, `reset`. No timers, no I/O.
- **`VisualContextBuilder`** — pure formatter: the last `N` keyframes → a `# Recent Visual Context`
  text with **relative** labels (`[T-30s] …`, `[Now] …`), and (optionally) a small multi-image
  message with the most recent at higher detail and older ones at "low" detail. Time is injected so
  the relative labels are deterministic.

## How it flows (live edge)
1. The change gate emits a **distinct** frame (a "major" change).
2. A **cheap, throttled describe** runs on that frame only — one short `analyzeFrame` /
   structured-vision call ("one line: what is the user looking at?"). Keyframes are rare (only on
   real scene change), so this is a small, bounded cost — not per-frame.
3. The `Keyframe` (description + thumbnail) is appended to `VisualStateMemory`.
4. On the next agent turn, `VisualContextBuilder` injects the compact "Recent Visual Context" text
   into the system/turn prompt (and, behind a flag, the recent thumbnails).
5. Optionally, evicted/aged keyframe descriptions feed `BrainStore.shared.ingest` so "what did I see
   earlier today" is answerable after the session (the brain is the native-first memory substrate).

## Scope
In:
- `Sources/Services/Vision/Keyframe.swift`, `VisualStateMemory.swift` (pure ring buffer).
- `Sources/Services/Vision/VisualContextBuilder.swift` (pure text/messages builder).
- `Sources/Services/Vision/VisualStateService.swift` — the live glue: subscribe to the gate's
  distinct-frame signal, run the throttled describe, push keyframes, hand the context to the session.
- `GeminiLive/GeminiLiveSessionManager.swift` — inject the "Recent Visual Context" block when building
  the instruction (it already assembles a system instruction per turn).
- `Config` — `visualStateMemoryEnabled` (default off), `visualStateMaxKeyframes`,
  `visualStateDescribeMinInterval` (rate-limit the describe), `visualStateInjectThumbnails`.

Out (deferred):
- Embeddings / semantic retrieval over keyframes ("find when I last saw my keys") — v2; the ring
  buffer + descriptions are v1. (Pairs later with the Embedding Quality Upgrade.)
- Cross-session persistence beyond the optional BrainStore ingest — keep the live buffer in-memory.
- Reusing the buffer for the single-shot `analyzeFrame` path — this targets the *live* agent.

## Architecture — the seam
```swift
struct Keyframe: Identifiable, Equatable {
    let id: UUID; let capturedAt: Date; let description: String; let thumbnailRef: URL?
}

final class VisualStateMemory {                 // session-scoped, fixed capacity
    init(maxKeyframes: Int)
    func add(_ k: Keyframe); func recent(_ n: Int) -> [Keyframe]
    var latestDescription: String? { get };     func reset()
}

enum VisualContextBuilder {                      // pure; `now` injected
    static func summaryText(_ keyframes: [Keyframe], now: Date) -> String   // "# Recent Visual Context…"
}
```
`VisualStateService` owns the memory + the describe throttle and is the only place that touches the
camera/LLM; everything testable is in the pure buffer + builder. With
`visualStateMemoryEnabled == false`, the session instruction is built exactly as today.

## Build order
1. **`VisualStateMemory` + `VisualContextBuilder` + tests** — pure: eviction at capacity, `recent(n)`
   ordering, relative-timestamp formatting with an injected `now`, empty/one/many cases. No device.
2. **`VisualStateService`** — wire to the change gate's distinct-frame output + a rate-limited
   describe; push keyframes. (Describe + camera are device-pending to validate.)
3. **Prompt injection** — add the context block to `GeminiLiveSessionManager`'s instruction builder
   behind the flag; optional thumbnails behind a second flag.
4. **(Optional) BrainStore ingest** of aged keyframe descriptions for after-session recall.

## Tests
- `VisualStateMemory`: capacity eviction (oldest drops), `recent(n)` returns the last n in order,
  `latestDescription`, `reset` clears, session isolation.
- `VisualContextBuilder.summaryText`: empty → ""; relative labels computed from injected `now`
  (`[T-30s]`, `[Now]`); only described keyframes appear; respects the max-in-context cap.

## Open questions / decisions needed
- **Describe budget** — keyframes are rare (gate-driven), but each describe is an LLM call. Rate-limit
  hard (`visualStateDescribeMinInterval`), and consider the on-device VLM path for the one-liner so it
  stays free/offline. Surfaces in the [cost tracker](llm-cost-usage-tracker.md).
- **Inject text vs images** — text-only is cheap and usually enough ("you were looking at X"); gate
  thumbnails behind a flag for when the model genuinely needs to see the prior frame.
- **Buffer depth** — 5–8 keyframes covers "the last little while" without bloating the prompt; tune
  on-device.

## Why this matters
This turns the live agent from "what's in this one frame" into "what's been happening in front of
you," which is the whole point of always-on glasses. It rides directly on the change gate (distinct
frames = keyframes), keeps the expensive part (describe) rare and bounded, and lands its core as a
pure ring buffer + formatter that's fully tested without hardware — with the model-facing injection
behind a flag so nothing changes until we turn it on.
