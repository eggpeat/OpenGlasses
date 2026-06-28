# Plan AU — LLM Cost & Usage Tracker (per-session/model token + spend)

**Status:** 📋 Planned (not built). Net-new — OpenGlasses currently tracks **no** API usage or cost.
Deterministic core (pricing × tokens) is pure and fully headless-testable; the only live wiring is
reading each provider's usage block in `LLMService`. Surfaces in the existing `InsightsView`. No new
SPM dependency.

## The problem
OpenGlasses is a **multi-provider, bring-your-own-key** app — Anthropic, Gemini, OpenAI, plus custom
endpoints, each with different per-token pricing. A user pointing it at their own paid keys has **no
idea what a session costs** and no running total. `LLMService` doesn't even parse the `usage` block
the providers already return, so the data is being thrown away.

## What we build
A small usage-accounting layer:
- **Capture** the token counts every provider already reports (Anthropic `usage.input_tokens` /
  `output_tokens`; OpenAI `usage.prompt_tokens` / `completion_tokens`; Gemini
  `usageMetadata.promptTokenCount` / `candidatesTokenCount`).
- **Price** them with a per-model table → a `UsageRecord` (session, model, tokens in/out, est. USD,
  timestamp).
- **Persist** records locally (SQLite, like the other on-device stores) and roll them up.
- **Surface** a "Tokens & estimated cost" section in [InsightsView](../../OpenGlasses/Sources/App/Views/InsightsView.swift),
  which already shows a 7/30/90-day recap — by model, with a total.

### The deterministic core
- **`ModelPricing`** — `[modelId: (inputPer1M: Double, outputPer1M: Double)]`, seeded with the
  shipped models and overridable; an `estimate(model:tokensIn:tokensOut:) -> Double?` (nil for an
  unknown/unpriced model rather than a wrong number).
- **`UsageRecord`** — the row type.
- **`UsageRollup`** — pure aggregation: given records + a window, produce per-model + total
  tokens/cost. No I/O.

## Scope
In:
- `Sources/Services/Usage/ModelPricing.swift` (pure pricing).
- `Sources/Services/Usage/UsageModels.swift` (`UsageRecord`, `UsageRollup` result).
- `Sources/Services/Usage/UsageStore.swift` (SQLite persist + window query + rollup).
- `Sources/Services/LLMService.swift` — parse the usage block per provider, hand a `UsageRecord` to
  the store. One small addition per provider response path.
- `Sources/App/Views/InsightsView.swift` — a "Usage & Cost" section (per-model rows + total) over the
  existing day-window picker; a Settings affordance to edit/override pricing.

Out:
- Realtime (Gemini Live / OpenAI Realtime) audio-token billing — different meter; record what those
  APIs report if available, otherwise mark the session as "realtime (untracked tokens)" rather than
  guessing.
- Hard budget enforcement / cutoffs — surface spend first; an optional soft budget warning is a
  follow-up.

## Architecture — the seam
```swift
enum ModelPricing {
    struct Rate { let inputPer1M: Double; let outputPer1M: Double }
    static func estimate(model: String, tokensIn: Int, tokensOut: Int) -> Double?  // nil if unpriced
}

struct UsageRecord { let sessionId: String; let model: String
                     let tokensIn: Int; let tokensOut: Int; let costUSD: Double?; let at: Date }

enum UsageRollup {
    struct ModelTotal { let model: String; let tokensIn: Int; let tokensOut: Int; let costUSD: Double? }
    static func rollup(_ records: [UsageRecord], since: Date) -> (perModel: [ModelTotal], totalUSD: Double?)
}
```
`LLMService` builds a `UsageRecord` from the parsed usage and the active `sessionId`; `UsageStore`
persists and answers the rollup for `InsightsView`. Pricing lives in one table, overridable from
Settings (so a price change doesn't need a release).

## Build order
1. **`ModelPricing` + `UsageRollup` + tests** — pure: known tokens × known rates → known cost;
   unknown model → nil; multi-model + multi-record rollups sum correctly; window filtering. No I/O.
2. **`UsageStore`** — SQLite insert + windowed fetch (mirrors the existing on-device stores);
   round-trip + window tests.
3. **`LLMService` capture** — parse usage per provider; emit a record. Guard each parse (a missing
   usage block records 0/0, never crashes).
4. **`InsightsView` surface** — per-model rows + total under the day picker; Settings pricing editor.

## Tests
- `ModelPricing.estimate`: each shipped model prices correctly at a known token count; unknown model
  → nil; zero tokens → 0.
- `UsageRollup`: empty → zero/empty; multiple records across models aggregate; records outside the
  window are excluded; a single unpriced model makes `totalUSD` nil-aware (report tokens, omit its $).
- `UsageStore`: insert/fetch round-trips; window query boundaries; survives restart.

## Open questions / decisions needed
- **Pricing source of truth** — bundle a default table (accepting it drifts) + let Settings override,
  vs. fetch remotely. Start bundled + overridable; revisit if drift bites. (Note the existing
  per-region IAP pricing is a *separate* concern — this is API token cost.)
- **Unpriced models** — report tokens and omit the dollar figure (chosen) rather than guess.
- **Privacy** — usage records are local-only and never leave the device; make that explicit in the UI.

## Why this matters
For a BYO-key multi-provider app this is a missing table-stakes feature: users can't see what they're
spending. The data already arrives in every response and is currently discarded. The fix is a pure,
fully-tested pricing/rollup core plus a tiny capture hook and a section in a view that already exists —
high value, low risk, squarely in the deterministic-core-first house style.
