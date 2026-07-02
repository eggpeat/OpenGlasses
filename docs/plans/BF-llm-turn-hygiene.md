# Plan BF — LLM Turn Hygiene: history repair, image pruning, prompt caching

**Status:** 📋 Planned (audit round 12, priority 5)

## The problem
Three compounding defects in how `LLMService` manages the conversation it sends every turn:

1. **A malformed or aborted tool call poisons the conversation permanently.** When
   `stop_reason == "tool_use"`, the assistant message (with `tool_use` blocks) is appended to
   `conversationHistory` *before* results; a malformed block is skipped via
   `guard … else { continue }` **without a tool_result**, and a throw/cancellation mid-execution
   leaves the same dangling state (`LLMService.swift:1324-1330` Anthropic, `:1559-1565`
   OpenAI-compatible). Anthropic rejects every subsequent request containing a `tool_use` with no
   matching `tool_result` → the user hears "Sorry, I encountered an error" on **every turn** until
   the conversation is cleared.
2. **Photos accumulate in history and re-upload every turn.** The vision user message with the full
   base64 JPEG is appended to `conversationHistory` (`:1245` Anthropic; same pattern OpenAI/Gemini)
   and the entire history is the request body each turn. The token estimator counts an image block
   at the 50-token floor (`:631-643`), so compaction never fires on image weight. Every follow-up
   re-uploads all prior frames (~200–600 KB each, ~1,100–1,600 real input tokens per image, per
   turn) — real dollars and multi-second latency on cellular, compounding under smart-camera mode.
3. **No prompt caching.** The system prompt is huge and static per session (~280 lines of prose +
   ~100 tool schemas) and is re-billed uncached every turn. Anthropic `cache_control` (and the
   OpenAI equivalent) would cut input cost and time-to-first-token substantially. (The `claude-api`
   skill doc is the reference for current cache-TTL semantics when implementing.)

Also here (same file, same theme): OpenAI-compatible malformed tool args silently become `[:]`
(`:1567`) — the tool executes wrong instead of returning a parse error the model could correct.

## What we build
### The deterministic core: `HistoryHygiene`
A pure module (`Sources/Services/LLM/HistoryHygiene.swift`) operating on the message array before
each send:
- **`repairDanglingToolUse(history)`** — for every assistant `tool_use` id with no following
  `tool_result`, insert a synthetic error result (`"tool execution was interrupted"`); provider-
  shape-aware (Anthropic blocks, OpenAI `tool_calls`/`role:"tool"`, Gemini functionResponse).
- **`pruneImages(history, keep: N)`** — replace image blocks older than the newest N (default 1)
  with a text placeholder (`"[photo previously attached: <context line>]"`); never touches the
  newest exchange.
- **`estimateTokens`** fix — count image blocks at `bytes/1.5k` heuristic instead of the 50-token
  floor so compaction sees them.

At the call sites: append a synthetic error `tool_result` immediately when a block is skipped or
execution throws (belt), run `repairDanglingToolUse` before every send (braces), and return a
parse-error tool_result for undecodable OpenAI tool args instead of `[:]`.

### Prompt caching
- Anthropic: `cache_control: {type:"ephemeral"}` breakpoints on the system prompt and the tools
  array.
- OpenAI-compatible: rely on automatic prefix caching (nothing to send) — but stop *re-shuffling*
  the prefix: keep system + tools byte-stable across turns within a session (audit found the tool
  list is rebuilt per turn; make it deterministic order).
- Record cache-read/-write token counts into the existing `UsageTracker` (Plan AU) so the win is
  visible in Insights.

## Scope
In: the pure module, call-site wiring in all provider paths, caching headers/fields, estimator fix,
usage capture. Out: the provider-adapter refactor (Plan BG — this plan deliberately patches the
four existing loops minimally so it can ship first), context-compression redesign.

## Build order
1. `HistoryHygiene` + tests (fixture histories per provider shape: dangling id repaired; images
   pruned oldest-first, newest exchange untouched; estimator counts images).
2. Call-site wiring per provider + tests on the skip/throw paths.
3. Cache-control + deterministic tool ordering + usage capture.

## Tests
Pure fixtures (including a real captured malformed-tool-call transcript); an integration test that
a thrown tool execution leaves a sendable history (validated against the Anthropic schema shape);
estimator unit tests.

## Why this matters
Finding 1 is the worst *persistent* failure in the app — one bad tool call bricks the conversation.
Findings 2–3 are the largest per-turn cost/latency lever available, in a BYO-key app where the
user pays directly (Plan AU exists precisely because they care).
