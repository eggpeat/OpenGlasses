# Plan BN — Shared Remote-Action Consent Surface (one confirm, three plans)

**Status:** ✅ Shipped — P1 ([#205](https://github.com/straff2002/OpenGlasses/pull/205)) closed the
`code_agent confirm` self-approval hole (approval routes through `ToolConfirmationCoordinator` via
`confirmPendingActionViaUserPrompt`, user-originated only) + shared `RemoteActionConsentView` and
source-attributed `RemoteActionConsentRequest`; P2 threaded `origin` through `RemoteCommandPolicy`
+ audit with per-origin rate buckets (the BL P4 prerequisite). Tests: `RemoteActionConsentTests`,
`RemoteCommandOriginTests`, `AgentSessionTests`. Phase detail below is retained as the design record.
**Origin:** The 2026-07-10 review sweep found three plans independently converging on the same
missing affordance — a user-distinct confirm for remote/agentic actions — plus one live
vulnerability in the only confirm that exists today.

**Goal:** One consent surface (voice + HUD) and one origin-aware policy/audit spine, shared by:
- **Plan N** — `awaitingInput` before an agent push/PR (today TTS-only, and see the vulnerability
  below).
- **Plan BH** — remote-invoke capture consent (today `ToolConfirmationCoordinator`, the right
  pattern, but peer-blind).
- **Plan BL P4** — capture/act consent when an MCP peer drives the glasses (committed to reusing
  BH's machinery, which currently can't attribute callers).

---

## P1 — Fix the self-approval hole + unify the confirm 🔴

**The vulnerability (Plan N).** `code_agent {action:"confirm"}` (`AgentControlTool.swift:75-77`)
approves a pending irreversible agent action with **no user-distinct check** — any LLM turn can
call it, so a prompt-injected turn (web result, OCR'd sign, ambient caption — the BK P0 vector) can
confirm its own push. Contrast BH capture, which routes through `ToolConfirmationCoordinator` (a
real user prompt).

**Fix.**
1. Route `code_agent confirm` through `ToolConfirmationCoordinator` — the confirmation must
   originate from the wearer (wake-word turn / explicit UI tap), never from tool-call output.
2. Extract the coordinator's prompt surface into a shared **`RemoteActionConsentView`** (HUD card +
   spoken prompt + voice yes/no), consumed by N's `awaitingInput` (upgrading it from TTS-only —
   Plan N Phase 4's HUD confirm, re-scoped here as the shared view) and by BH capture unchanged.
3. Consent requests carry a **source line** ("The coding agent wants to push to main" / "The
   gateway wants a photo" / "Ops platform wants a photo") — same narration principle as BK P2c.

**Tests.** A `confirm` tool call without a pending user-originated grant is refused; the
coordinator grant path still approves; N's awaitingInput decline still cancels (existing
`AgentSessionTests` stay green); consent prompt includes the source.

---

## P2 — Origin-aware policy + audit (the BL P4 seam) 🟠

**The gap (Plan BH, verified).** `RemoteCommandPolicy.decide(command:agentModeEnabled:toggles:rateState:now:)`
(`RemoteCommandPolicy.swift:99-105`) takes no caller identity; `RemoteInvokeAuditEntry` records
only action+disposition; rate state is one shared bucket set. Consequences: a chatty MCP peer
starves the gateway's rate budget, audit entries can't be attributed, and BL P4's "every call
attributed to the peer's API key" is unimplementable on the shipped seam.

**Fix.**
1. Thread an `origin` (`gateway` / `mcpPeer(id:)` / future callers) through `decide()` and the
   audit entry.
2. Key token-bucket rate state per origin.
3. Per-origin rows in the existing Gateway-settings activity log.
4. Cross-reference: outbound gateway-socket identity is Plan AR (`deviceId`/Ed25519); inbound peer
   identity is the peer's API key (BL P4) — one identity story, two transports, no second
   mechanism.

**Tests.** Pure policy: same command, two origins → independent buckets; audit entry carries
origin; existing `RemoteCommandPolicy` tests unchanged for the gateway origin.

---

## Sequencing

P1 is independent and closes a real injection→push hole — ship early. P2 lands **before BL PR4**
(it's BL P4's named prerequisite) and is pure-core refactor work, headless. Both PRs follow house
style: deterministic core + tests first, UI wiring thin.
