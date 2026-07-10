# Plan BL — Ops-Platform Agent Bridge (two-way A2A + MCP)

**Status:** 📋 Planned
**Goal:** Let the wearer's OpenGlasses agent and an **external multi-domain operations platform**
exchange agent messages both ways — the user can ask/answer from the glasses *and* the platform can
push updates the wearer hears and replies to — **and** expose the glasses' own capabilities (camera,
location, device state, announce, a scoped agent turn) to the platform as MCP tools. The result is one
conversation spanning phone-glasses and the ops app, with the glasses as a perceivable, actionable node
— not two isolated assistants.

The peer is any agent platform that speaks the two open protocols OpenGlasses already implements:
**A2A** (agent-to-agent, JSON-RPC 2.0 task submit/poll) and **MCP** (tool list/call + SSE). This plan
is written against those protocols, not a specific product, so any conforming peer works. Peer-side
changes are documented as a contract only — **this plan touches the OpenGlasses repo alone.**

House style: deterministic, headless-testable core first; the live socket/backend edge deferred; one PR
per phase. The inbound direction (glasses → platform) ships first as the smaller, lower-risk slice.

---

## Why this is mostly assembly, not new protocol

Both sides already carry the needed surfaces:

**OpenGlasses (this repo):**
- Outbound MCP client — `MCPClient.swift`, `MCP/MCPTransport.swift`, `MCP/SSEEventParser.swift` (Plan V)
  — can list/call a remote MCP server and consume an SSE stream.
- One-tap remote-server install + trust UI — `MCP/MCPCatalog.swift` (Plan V).
- Inbound dev server — `MCPServer/MCPGlassesServer.swift` exposes `/send_to_glasses` (TTS+HUD),
  `/see_glasses`, `/glasses_status`, bearer-token authed, gated behind `agentModeEnabled` +
  `mcpServerEnabled` (Plan BC).
- Egress + tool-poisoning screen for third-party MCP tools — `SecretPatterns`/`EgressScreen`/
  `ToolDefinitionScanner` (Plan R).
- Gateway message primitives — `OpenClawBridge.routeMessage`/`listChannels` (`OpenClawBridge.swift:652`).
- The narration principle for automatic actions — Plan [[BK-adversarial-review-remediation]] P2c.

**Peer contract (A2A + MCP, out of this repo):**
- A2A: `POST /a2a` JSON-RPC — `tasks.send` (submit), `tasks.get` (poll), `agent.getCard`; `X-API-Key` auth.
- MCP server: `GET …/mcp/tools`, `POST …/mcp/tools/call`, `GET …/mcp/sse`; `X-API-Key` auth.
- A `glasses`-topic alert event on that SSE stream (replayable), carrying a correlation id — the
  glasses subscribe out; the peer never calls into the phone (see contract section).

The only genuinely new build is the reply-correlation loop and an OpenGlasses-side `ops_task` tool;
everything else is configuration + thin adapters over existing code.

---

## P1 — Glasses → platform (inbound to the peer) 🟢 PR1

**What the user gets.** From the glasses: *"Ask ops about the gate-12 delay"* or *"Log a delay on line
3, cause unknown."* The glasses agent reaches the platform, gets a real answer or a task acknowledgment,
and speaks it.

**Two complementary paths (ship both; they serve different latencies):**
1. **Synchronous query via MCP.** Register the peer as a remote MCP server through the existing
   `MCPCatalog` install (base URL + `X-API-Key`, stored in Keychain). The peer's domain tools then
   appear to the agent like any other MCP tools and route through `MCPClient`. Best for "look something
   up / take one action, answer now."
   *Work item:* the catalog install flow today only prefills `Authorization: Bearer …`
   (`MCPCatalog.swift:113`); the transport already applies arbitrary `server.headers`
   (`MCPTransport.swift:90`), so P1 adds a **custom auth-header option** (header name + value, e.g.
   `X-API-Key`) to the install/trust UI — small, but it's the difference between "existing install"
   and reality.
2. **Async task via A2A.** A native `ops_task` tool (`NativeTool`) that POSTs `tasks.send`, gets a
   `taskId`, and either polls `tasks.get` to completion (short) or registers the id for a later push
   result (long-running). Best for "kick off an investigation / multi-step ops work."
   *PR1 honesty rule:* the push channel doesn't exist until P2, so in PR1 pending `taskId`s are
   **persisted** and checked on the next agent wake ("your ops task from earlier finished: …") — the
   tool must not promise a callback nothing delivers. P2 upgrades this to a real push.

**Feature detection.** Use `agent.getCard` at install/configure time to discover what the peer
supports (glasses alert channel, `submitReply`, task continuation). The bridge degrades gracefully to
P1-only against a peer whose card lacks the push/reply extensions — no config toggles to guess at.

**Deterministic core (headless-testable, no network):**
- `A2AClient` — pure JSON-RPC 2.0 request builder + response/`error` decoder for `tasks.send`/
  `tasks.get`/`agent.getCard`; maps A2A `error.code` to typed Swift errors. Transport injected.
- `A2ATaskPoller` — pure state machine over `tasks.get` states (`submitted`/`working`/`completed`/
  `failed`) with a bounded backoff schedule and a terminal classifier. No timers in the core; the live
  layer drives ticks.
- `OpsTaskTool` — wraps the above; returns the completed result string (spoken), or an honest
  "working, I'll check next time we talk" when the task is async (persisted pending id; upgraded to a
  push in P2).
- `MockOpsPeer` — a `URLProtocol`-backed test double speaking the peer contract (A2A + MCP + the P2
  alert stream). Built once here, **extended each phase**, so PR3 can land a headless test of the whole
  conversation: task sent → alert pushed → reply routed → continuation received. This is the
  integration gate the per-component unit tests don't give us.

**Gating & safety (non-negotiable, mirrors the Plan BK P0 finding):**
- The whole bridge sits behind `agentModeEnabled` at the **service/execution** level, not just UI — a
  configured peer must not be reachable with agent mode off. `OpsTaskTool.execute` and the peer-MCP
  routing both guard on it.
- Inbound peer MCP tool definitions run through the Plan R `ToolDefinitionScanner`; peer tool *output*
  is treated as untrusted and wrapped by the existing `PromptInjectionPolicy` before it re-enters the
  LLM (the peer can act on the wearer's device, so its text must never be trusted instructions).
- `X-API-Key` in Keychain; egress screened by `EgressScreen`/`SecretPatterns` per the peer's policy.

**Spoken failure UX.** The whole bridge is voice-first, so typed errors aren't enough: each error
class maps to a short spoken string — peer unreachable, auth rejected (401), task failed, timed out —
via a small tested table, not ad-hoc strings at call sites.

**Usage accounting (Plan AU hook).** Peer calls aren't on-device LLM tokens — don't invent pricing.
P1 counts `ops_task`/peer-MCP calls per session (its own row kind — `UsageTracker.record` drops
0-token records), and if the peer's A2A responses carry usage metadata, record it as unpriced
tokens (nil cost), the house posture for unpriced models.

**Tests.** `A2AClient` builds a spec-correct `tasks.send` envelope and decodes success/`error`;
`A2ATaskPoller` transitions to `completed`/`failed` and honours the attempt cap; `OpsTaskTool` returns
the result on sync completion and the deferred message on async; a pending task persisted in PR1 is
reported on the next wake; each error class yields its spoken string; agent-mode-off ⇒ tool returns a
disabled message and no request is emitted.

---

## P2 — Platform → glasses (push updates to the wearer) 🟡 PR2

**What the user gets.** The ops platform raises something the wearer should know — *"Gate 12 just went
red, ETA slip 40 minutes"* — and it arrives on the glasses as speech + HUD, unprompted, with a short
earcon first.

**Mechanism — subscribe outbound, don't listen inbound.** The wrong shape here is "the peer calls
into the phone": `MCPGlassesServer` is an `NWListener` inside the app process, and iOS suspends it the
moment the app backgrounds or the phone locks — an inbound push would silently never arrive outside a
demo posture. Same lifecycle constraint as on-device inference ([[project_local_model_background]]).
So the **primary transport is an outbound SSE subscription**: the glasses app subscribes to the peer's
existing `…/mcp/sse` stream (a `glasses`-topic event carries `{ message, correlationId, severity }`),
reusing `SSEEventParser` (Plan V). "Push" becomes "the client is subscribed" — no inbound reachability
problem, works behind NAT, and the peer never needs to reach into a phone. `/send_to_glasses` stays as
the LAN/dev path it already is (and gains nothing new here).

**Lifecycle & catch-up.** The subscription lives only while the app is foregrounded/active — that's an
iOS fact, not a bug, and the plan owns it: alerts raised while suspended **queue peer-side and replay
on reconnect** (SSE `Last-Event-ID`), surfaced as a batched "While you were away: …" summary rather
than a stale one-by-one blast. APNs would close the background gap fully but drags in push
infrastructure — **explicitly out of scope** for this plan; the SSE + replay posture is the committed
v1.

**Deterministic core (OpenGlasses side):**
- `OpsUpdateEnvelope` — pure decoder/validator for the alert payload (message, correlationId,
  severity, optional expected-reply hint). Enforces **alert-text hygiene** at the boundary: length cap
  + TTS sanitization (no SSML/control sequences); the message is spoken verbatim to the wearer and
  later sits in LLM context (P3 reply routing), so it is untrusted input twice over — anything that
  crosses into LLM context is wrapped by `PromptInjectionPolicy`, same as P1 tool output.
- `OpsUpdateRouter` — maps severity → `SpeechUrgency` and decides speak-now vs queue-when-idle (respect
  the presence/throttle policy, Plan W — don't interrupt a live turn or blast the wearer when away).
  Plan W governs *when* to speak; the router adds the *how many*: a **flood rule** (max N spoken alerts
  per window, duplicates collapsed, overflow summarized as "…and 3 more ops alerts").
- `OpsAlertReplayCursor` — pure `Last-Event-ID` bookkeeping + the batch/summarize decision for alerts
  that arrived while suspended.
- Narration: reuse Plan BK P2c — announce the source ("Message from ops:") so the wearer knows it's an
  external update, not the local agent talking. Earcon precedes speech.

**Auth/gating.** The subscription inherits the peer's `X-API-Key` (Keychain) and sits behind
`agentModeEnabled` at the service layer — agent mode off ⇒ no subscription exists, not merely no
speech. A push with an unknown/stale `correlationId` is still spoken (it's a valid alert) but starts
no reply thread.

**Tests.** Envelope decoder rejects malformed payloads, caps length, and strips control sequences;
router maps `critical` → high urgency + speak-now and `info` → queue-when-idle; flood rule collapses
duplicates and summarizes overflow; away-presence suppresses per Plan W; replay cursor batches
missed alerts into one summary; narration prefixes the source once; agent-mode-off ⇒ no subscription
started.

---

## P3 — Round-trip reply (the wearer answers back) 🟡 PR3

**What the user gets.** After a pushed update the wearer just talks: *"Tell them to hold the truck, I'm
5 minutes out."* That reply routes back to the platform against the same conversation, so the ops app
sees the answer — a genuine two-way exchange, not a one-way alert.

**Mechanism.** The P2 push carried a `correlationId`. OpenGlasses keeps a small `OpsReplyRegistry`
(pure, bounded) mapping the active correlation id to its origin. The wearer's reply is sent back via
A2A `tasks.send` as a continuation referencing that id (or an MCP `submitReply` tool call if the peer
prefers MCP), and the loop can continue.

**How the reply is heard — committed for v1.** The app is wake-word driven, and a pushed alert does
**not** arm the mic. In v1 the wearer replies the normal way: wake word, then either an explicit
intent ("reply to ops: hold the truck") or a plain follow-up inside the post-push window. An
auto-armed hands-free listening window after an alert is the harder feature — it touches the wake →
transcription pipeline in `OpenGlassesApp` and has its own privacy story — and is **deferred as a
follow-up**, not smuggled into PR3. The concrete integration point for reply classification is the
turn pipeline's handler chain (Plan BG): `OpsReplyRouter` runs as a handler ahead of normal LLM
dispatch when a thread is open.

**Egress.** The reply body is wearer speech leaving the device — it goes through
`EgressScreen`/`SecretPatterns` exactly like P1 outbound calls before `tasks.send` fires.

**Deterministic core:**
- `OpsReplyRegistry` — correlation-id → context, with TTL/expiry and a single-active-thread rule so a
  stale thread can't hijack a fresh reply.
- `OpsReplyRouter` — decides whether a given spoken turn is a reply to the open ops thread vs a normal
  local turn (explicit-intent first; a short post-push window as a soft signal), and builds the A2A
  continuation.

**Guardrails.** Never silently divert a normal command into the ops thread — require an explicit reply
intent or an unambiguous within-window follow-up; otherwise treat it as a local turn. Expire threads so
"reply to ops" can't attach to an hour-old alert.

**Tests.** Registry expires by TTL and keeps one active thread; router classifies an explicit reply vs a
normal command vs an ambiguous case (defaults to local); continuation envelope references the right id;
reply text passes the egress screen before send; the `MockOpsPeer` round-trip test runs the full loop
(task sent → alert pushed → reply routed → continuation received) headless.

---

## P4 — Expose the glasses' own capabilities as MCP tools 🟡 PR4

**What the user gets.** The ops platform (as an MCP *client*) can query and use the wearer's glasses
directly: *"what's the operator seeing at gate 12?"* pulls the live camera frame; the platform can read
the wearer's location/heading, device status, and push a HUD/voice message — and, optionally, run a
scoped glasses-agent turn. This turns the glasses into a first-class node the ops platform can perceive
and act through, not just a chat endpoint.

**Today's gap.** `MCPGlassesServer.swift` is **not** an MCP server — it's three hardcoded REST endpoints
(`/see_glasses`, `/glasses_status`, `/send_to_glasses`) with no `tools/list` or `tools/call`, reachable
only on the LAN (`en0`, `MCPGlassesServer.swift:132`). A remote MCP client can't discover or call it.

**Build.**
1. **Real MCP surface.** Add `GET …/mcp/tools` (return tool schemas) and `POST …/mcp/tools/call`
   (JSON-RPC dispatch) to `MCPGlassesServer`, keeping the existing REST endpoints as thin aliases so the
   current Mac stdio bridge (Plan E) still works. Bearer-token auth and the
   `agentModeEnabled`+`mcpServerEnabled` gate stay exactly as they are (`MCPGlassesServer.swift:78,166`).
2. **Capability tool set,** grouped by risk so each group has its own consent toggle:
   - **Read (low):** `glasses_status`, `battery`/`thermal` (device state), `location`/`heading`
     (from `LocationService`), `ambient_caption_snapshot` (last N captions if that feature is on).
   - **See (capture — high):** `see_glasses` (latest frame) and `capture_photo`. Treated as a capture
     action, not a passive read.
   - **Act (high):** `announce` (TTS + HUD, the current `send_to_glasses`), `show_hud_card`.
   - **Agent (highest, opt-in):** `ask_glasses_agent` — runs one scoped local turn and returns the
     reply, so the platform can delegate a question to the on-glasses agent. **When invoked by a remote
     peer it runs a *restricted, read-only* turn** (no acting tools, no memory writes) in v1; a full
     turn (tools + memory) is available only behind an explicit separate toggle, default off.
     **No capability escalation through the turn:** the scoped turn's toolset is **intersected with
     the peer's granted capability groups** — a peer with Agent granted but See denied gets a turn
     that cannot invoke any capture/vision tool, so "what's the operator seeing?" can't route around
     the See toggle via the agent. And a capture inside a *granted* turn still fires the Plan BH
     confirm→announce→act flow; the agent wrapper never bypasses per-call consent.
3. **Reachability for a remote peer.** The peer is off-LAN, so the default surface binds/advertises over
   the wearer's private mesh network (Greig runs Tailscale — [[user_greig]]) rather than opening `:8765`
   to the public internet. The server keeps the bearer token on top of the private-network boundary; no
   port-forward, no public exposure. **Both reachability modes are offered:** mesh (default, for remote)
   **and an explicit LAN grant** (opt-in toggle, for on-site use where the peer is on the same network);
   the existing LAN dev bridge continues to work under the LAN grant.

**Consent & safety — reuse RemoteInvoke, don't reinvent it.** Exposing camera/location/actions to a
remote caller is the **same threat model** as Plan BH (Gateway Remote Invoke), which already ships the
right machinery: deny-by-default, per-class user toggles, **capture consent OFF by default**,
confirm→announce→act for capture, token-bucket rate limits, and an audit log. Route every `See`/`Act`/
`Agent` MCP tool-call through the existing `RemoteCommandPolicy`/`RemoteCommandExecutor` so a peer
pulling the camera triggers the same pre-action TTS announcement and consent the wearer already gets for
gateway capture. `Read`-group tools are allowed under a lighter per-capability toggle. Every call is
audited and attributed to the peer's API key.

**Deterministic core (headless-testable):**
- `GlassesMCPToolRegistry` — pure tool-schema list + a dispatch table mapping tool name → capability
  group. No socket.
- `GlassesCapabilityPolicy` — pure decision `(toolName, peerId, toggles) → allow / deny / needs-capture-
  consent`, delegating See/Act/Agent to the Plan BH policy. Unit-tested exhaustively.
- The live `MCPGlassesServer` becomes a thin transport over these two + the existing executor.

**Gating & default posture (committed).** All of P4 inherits `agentModeEnabled` + `mcpServerEnabled`;
each capability group has its own toggle in MCP Server settings. **Defaults: Read on; See, Act, and Agent
off** — the wearer opts into anything that captures, acts, or runs the agent. A peer with no granted
capabilities can still reach `tools/list` but every `call` returns a policy denial.

**Tests.** `tools/list` returns only granted capabilities; a `See` call with capture-consent off is
denied with the Plan BH reason; a `Read` call under its toggle succeeds; policy denies an unknown tool
and an unauthorized peer; **Agent granted + See denied ⇒ the scoped turn cannot capture** (the
escalation test); a capture inside a granted turn still triggers confirm→announce→act; the announce
path still speaks; agent-mode-off ⇒ server not started, no surface at all.

---

## Peer-side contract (out of this repo — documented, not built here)

For a conforming peer to complete the loop, its side needs:
1. A2A `tasks.send`/`tasks.get` accepting the wearer's submissions (standard A2A — typically already
   present).
2. An MCP server exposing the domain tools the wearer may call (standard MCP — typically already
   present).
3. A **`glasses`-topic event on its existing SSE stream** (`…/mcp/sse`) carrying
   `{ message, correlationId, severity }`, with **replayable event ids** (`Last-Event-ID`) so alerts
   raised while the app was suspended are delivered on reconnect; and it accepts the wearer's reply
   back on the correlation id (via A2A continuation or an MCP `submitReply` tool). The peer never
   calls into the phone — the glasses subscribe out.
4. Its `agent.getCard` advertises which of these extensions it supports (glasses channel,
   `submitReply`, continuations), so the app can feature-detect instead of being configured by hand.

**Correlation-id namespace (pinned).** `correlationId` **is the A2A `taskId`** when the alert is the
result of a task the wearer submitted; for unsolicited alerts the peer mints an id in the same field.
A P3 reply is an A2A continuation (`tasks.send` with a `replyTo: correlationId`) — or the
`submitReply` MCP tool where the peer prefers it — identical in both cases, so OpenGlasses never
branches on how the thread began.

Items 1–2 are usually already shipped on an A2A+MCP platform; items 3–4 are the deliberate additions
(and publishing to an existing SSE stream is a far smaller ask than learning to reach a phone).

For **P4**, the peer needs nothing new — it already has an MCP *client*; it just points that client at
the wearer's `…/mcp` surface (over the private mesh network) with the glasses' bearer token, and the
glasses' capability tools appear alongside the platform's own.

---

## Sequencing & scope

- **PR1 = P1** (glasses → platform): highest reuse, nothing new required on the peer, immediately useful
  on its own (query/act on the ops platform hands-free).
- **PR2 = P2** (platform → glasses): needs the peer's `glasses`-topic SSE events; OpenGlasses side is
  an outbound subscription (`SSEEventParser` reuse) + envelope/router/replay-cursor core.
- **PR3 = P3** (reply loop): closes the conversation.
- **PR4 = P4** (expose glasses capabilities as MCP tools): the platform can perceive/act through the
  glasses. Sequenced last because it's the largest consent surface — but it's a **committed part of the
  plan**, not optional. It reuses the Plan BH consent machinery, so the risk is bounded.
- All phases inherit the Plan BK P0 lesson — gate at the service layer, screen untrusted peer output,
  and reuse Plan R/BC/W/BH rather than re-inventing auth, egress, presence, or capture-consent handling.

**Resolved decisions (2026-07-10).**
- `ask_glasses_agent` (P4) runs a **restricted, read-only** turn for a remote peer in v1; full-turn access
  is a separate explicit toggle, default off. The turn's toolset is intersected with the peer's granted
  capability groups (no escalation through the agent).
- Reachability offers **both** the private-mesh (Tailscale) default **and** an explicit LAN grant for
  on-site use.
- Capability defaults: **Read on; See/Act/Agent off.**
- **P2 transport is outbound SSE subscription** (glasses subscribe to the peer's stream), not the peer
  calling into the phone — the iOS lifecycle makes an inbound listener a demo-only posture. Missed
  alerts replay on reconnect (`Last-Event-ID`); APNs is explicitly out of scope.
- **P3 v1 reply is wake-word initiated** (explicit intent or in-window follow-up); an auto-armed
  post-alert listening window is deferred as its own follow-up.
- `correlationId` == A2A `taskId` for task results; peer-minted for unsolicited alerts; replies are
  uniform continuations either way.

**Open question (still).**
- Transport preference when both A2A and MCP can serve a request (default: MCP for synchronous
  query/act, A2A for long-running tasks).
