# Plan BC — Unconditional Tool Safety Gate & MCP Server Auth

**Status:** ✅ Shipped ([#157](https://github.com/straff2002/OpenGlasses/pull/157)) — `HighImpactToolPolicy` confirmation regardless of Agent Mode; `MCPGlassesServer` bearer-token auth (Keychain, shown in Settings); `URLFetchGuard` SSRF screen in `QRContextTool` (`SafetyGateTests`).

## The problem
Two high-severity security findings from the July 2026 audit:

1. **The safety supervisor and confirmation gate only run in Agent Mode.**
   `NativeToolRouter.swift:59` wraps the entire `SafetySupervisor.evaluate` +
   `ToolConfirmationCoordinator` block in `if Config.agentModeEnabled` — which defaults to `false`.
   In the default mode, tool calls go straight to `tool.execute()`. The messaging tools are naturally
   gated (URL schemes require a user tap in the target app), but the tools that **act directly** are
   not: `smart_home` (HomeKit — including **`unlock`** on doors/locks) and `home_assistant`.
   Failure scenario: prompt-injected text from any untrusted surface (ambient caption of a bystander,
   a web-search result, a scanned QR/sign) talks the model into
   `smart_home action:unlock device:"front door"` — it executes immediately with zero
   human-in-the-loop. The `PromptInjectionPolicy` envelope is a soft mitigation, not a gate.

2. **The embedded MCP glasses server is an unauthenticated LAN camera feed.**
   `MCPGlassesServer.swift:45-171` — `NWListener` on TCP `:8765` serves `GET /see_glasses`
   (base64 JPEG of the live camera frame), `GET /glasses_status`, and `POST /send_to_glasses`
   (makes the glasses speak arbitrary text). `route()` performs no token or origin check: anyone on
   the same Wi-Fi can pull the wearer's camera view or make the device talk. The settings UI even
   suggests exposing it publicly via `cloudflared tunnel` (`MCPServerSettingsView.swift:43`).

Lesser, same theme: `QRContextTool.swift:81-118` fetches any scanned/LLM-supplied `http(s)` URL
unrestricted — a malicious QR can point at `http://192.168.x.x/…` or a metadata host and exfiltrate
the first 8 KB back through the model (SSRF-shaped).

## What we build
### 1. Unconditional gate for direct-actuation tools
- A deterministic **`HighImpactToolPolicy`**: a pure classification of (tool, args) →
  `.proceed` / `.requiresConfirmation` / `.deny`. Seed set: `smart_home` and `home_assistant`
  actuation verbs (unlock/open/disarm/off for security-relevant device classes), `medical_export`,
  `execute` (gateway). Reads: always `.proceed`.
- `NativeToolRouter` runs this policy **before** the agent-mode block, regardless of
  `Config.agentModeEnabled`. Confirmation = the existing voice-approval path when available, else
  the phone confirmation sheet (`ToolConfirmationCoordinator` already exists — this plan widens
  when it runs, not what it does).
- The full `SafetySupervisor` (geofence/quiet-hours/plan validation) stays agent-mode-gated as
  designed — agentic/autonomous features remain behind `agentModeEnabled`. This plan only makes the
  *irreversible-actuation confirmation* unconditional: that's a user-safety floor, not an agentic
  feature.

### 2. MCP glasses server auth
- Generate a per-enable **bearer token** (CryptoKit random, shown/copyable in
  `MCPServerSettingsView`, stored in Keychain); `route()` rejects requests without
  `Authorization: Bearer <token>` (constant-time compare).
- Bind to loopback by default with an explicit "LAN" toggle; remove the `cloudflared` suggestion
  from the settings copy (or caveat it hard).

### 3. QR/URL fetch guard
- A pure **`URLFetchGuard`**: scheme allowlist (http/https) + deny private/loopback/link-local/
  `.local`/metadata ranges (resolve host, check all addresses). Applied in `QRContextTool` (and any
  future generic fetch tool).

## Scope
In: the three items above + tests. Out: broadening `SafetySupervisor` itself, MCP *client* trust
work (Plan R/V territory), any new tools.

## Build order
1. `HighImpactToolPolicy` + tests (pure: every seed tool/verb matrix → expected verdict; reads pass;
   unknown tools pass).
2. Router wiring + tests (agent mode off → confirmation still demanded for `unlock`; denial path
   returns a spoken-friendly refusal string).
3. `URLFetchGuard` + tests (private ranges, redirects to private ranges, `.local`, IPv6 link-local).
4. MCP server token: generation, Keychain storage, `route()` check + tests on the pure route/auth
   function; Settings UI copy.

## Why this matters
"Glasses that can unlock your front door because a stranger's sign said so" is the single worst
headline this product could generate. The fix is small, pure, and testable — and it aligns with the
existing safety architecture rather than replacing it.
