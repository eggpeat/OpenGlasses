# Plan AI — LLM Provider Auth & Fallbacks (reference)

How OpenGlasses can authenticate to an LLM backend, what each path costs in
*functionality*, and where OAuth / "use my account" actually works.

## The governing principle

**Full functionality** = the app sends a real chat/vision request with our system
prompt, camera images, tool definitions, and gets back streamed text + structured
tool calls. That needs a genuine **completions API**.

A consumer **subscription** (ChatGPT Plus, Gemini Advanced / Google One AI, Claude
Pro/Max) does **not** expose such an API to third‑party apps — it only powers the
vendor's own app. So "use my flat subscription as OpenGlasses' brain, no per‑token
cost, full features" is **not possible for any provider**. OAuth + full functionality
coexist only on the **cloud enterprise endpoints**, which are still billed per token —
OAuth just replaces the raw API key with an account‑scoped token.

## Consumer‑subscription login (no key) — current reality (mid‑2026)

The thing most users actually want — *"press Sign in with Google/ChatGPT, use the AI I
already pay for, never touch an API key"* — **does not robustly exist for any provider yet:**

- **OpenAI / ChatGPT — emerging, the one to watch.** OpenAI is building **"Sign in with
  ChatGPT"** (OAuth 2.0), with a proposed **"user plan"** option so requests run under the
  *user's own ChatGPT subscription* instead of the developer paying. This is exactly the
  model we'd want — but it's **preview only** (first surfaced in Codex CLI), not a GA
  integration a third‑party app can ship against today. Design for it; don't depend on it.
- **Google / Gemini — no, and the workaround is now banned.** Google AI Pro / Gemini
  Advanced (the consumer subscription) **includes no API access**. Worse: the trick of
  proxying a Gemini‑CLI **OAuth token** to use a user's Pro/Ultra quota was **banned in
  Feb 2026, with mass account suspensions — including paying Ultra subscribers.** Do not
  build on it. The only no‑key Google path is **Vertex OAuth**, which bills a GCP project
  per token — *not* your Gemini Advanced subscription.
- **Anthropic / Claude — no login button.** Only the local `claude -p` CLI bridge (ToS
  gray area) or the on‑device Claude‑app Shortcut (text‑only). No OAuth‑subscription API.

**Takeaway:** keep the provider layer ready to slot in "Sign in with ChatGPT" if/when it
GAs, but today every *full‑functionality* path needs either an API key or a per‑token cloud
OAuth account. The only "no key, uses my subscription, works now" option is the text‑only
Claude‑app Shortcut.

## Auth-path matrix

| Path | Auth | Vision + native tools | Who bills | In OpenGlasses |
|---|---|---|---|---|
| **Anthropic API** | API key | ✅ full | Anthropic (key) | ✅ supported |
| **Claude via local CLI bridge** | OAuth (Claude Code `claude login` on a Mac/host) | ✅ full | Claude subscription* | ✅ client done (keyless Custom provider); needs the host bridge |
| **Claude app "Ask Claude"** (Shortcut) | OAuth (on‑device Claude app) | ❌ **text only, no tools** | Claude subscription usage | ➕ fallback (this doc) |
| **OpenAI API** | API key | ✅ full | OpenAI (key) | ✅ supported |
| **Azure OpenAI** | **Microsoft Entra OAuth** | ✅ full | Azure (account) | ⚠️ via Custom provider; needs token refresh |
| **Gemini API (AI Studio)** | API key (created via Google sign‑in) | ✅ full | Google (free tier + per‑token) | ✅ supported (Gemini provider) |
| **Gemini via Vertex AI** | **Google OAuth** (GCP project) | ✅ full | Google Cloud (account) | ⚠️ needs OAuth plumbing |
| **AWS Bedrock** | AWS SigV4 / IAM | ✅ full | AWS (account) | ⚠️ needs signing |

\* Using a Claude *subscription* via the CLI to serve app requests is a ToS gray area
(subscriptions are for interactive Claude Code use). The sanctioned programmatic path is
an API key.

## "Through my Google account" — the specifics

**Gemini (Google's own model) — yes, two ways, both full‑featured:**
1. **AI Studio key (easy, already supported).** Sign in to `aistudio.google.com` with the
   Google account → create an API key → paste into OpenGlasses' Gemini provider. Has a free
   tier. The credential is a key, not OAuth, but it's "through your Google account" in the
   sign‑in sense, and it's the lowest‑effort full‑functionality path.
2. **Vertex AI + OAuth (true OAuth, more work).** A Google Cloud project with Vertex AI
   enabled; Google Sign‑In requesting the `cloud-platform` scope → exchange for a Bearer
   token → call Gemini on `aiplatform.googleapis.com` with full vision/tools/streaming.
   Billed to GCP. Requires new OAuth + token‑refresh code in the app.

**OpenAI — no, not "through Google."** OpenAI and Google are different vendors; your Google
account can't pay for OpenAI usage. The only Google link is **SSO**: you may *log in* to the
OpenAI platform with "Sign in with Google", but you still create an **OpenAI API key** billed
to your OpenAI account. There is no OAuth flow to drive the OpenAI API from a ChatGPT Plus
subscription. (The OpenAI API counterpart to "OAuth + full functionality" is **Azure OpenAI**
via Microsoft Entra — a Microsoft account, not Google.)

## Documented fallback — "Claude app (Shortcut)" provider

A **text‑only** path that uses the on‑device Claude app's subscription, no API key, no Mac.

Flow:
```
OpenGlasses builds a prompt
  → opens  shortcuts://x-callback-url/run-shortcut
             ?name=<AskClaudeShortcut>&input=text&text=<prompt>
             &x-success=openglasses://claude-result
  → the (user‑installed) Shortcut runs the Claude app's "Ask Claude" App Intent
  → returns Claude's text to OpenGlasses' URL handler via x-success
```

What it gives: a chat answer on the user's Claude subscription (counts against usage),
using the Claude app's default model.

Hard limits (why it's a fallback, not the brain):
- **No vision.** "Ask Claude" is text‑only; photo handling is a separate Control, not a
  pipeable returning action. The glasses‑camera loop can't use this.
- **No native tools / agent mode** — returns plain text, nothing callable.
- **No injected persona/memory/history** beyond what's stuffed into the prompt string.
- **Foreground hop per query** — a third‑party app can't run a Shortcut invisibly, so the
  Shortcuts app (and likely Claude) flashes up each call. Breaks hands‑free use.
- **No streaming;** subject to normal subscription usage limits.

Open items before shipping it:
- Verify with a one‑Shortcut test whether "Ask Claude" returns headlessly and how the
  result comes back (x‑callback vs. clipboard).
- Surface a loud "text‑only, no vision/tools, app‑switch per query" warning in the picker.
- Reuse the existing Shortcuts/App Intents integration (see `Z-shortcuts-catalog`) and the
  app's deep‑link handler (already parses `fb-viewapp://` etc.).

## Recommendation
- Want **full functionality with the least effort** → **Gemini via AI Studio key** (Google
  sign‑in), already supported.
- Want **true OAuth, no raw key, full functionality** → **Gemini via Vertex AI** (Google
  account) or **Azure OpenAI** (Microsoft) — both real features to build (OAuth + token
  refresh), both billed per token.
- Want **Claude on the subscription, full features** → the **local `claude -p` bridge**
  behind the keyless Custom provider (needs a Mac/host).
- The **Claude‑app Shortcut** is the no‑key/no‑Mac fallback, but text‑only — document it as
  such, don't position it as primary.
