# Plan — Teleprompter (audio-paced HUD script)

**Status:** ✅ Built (Phases 1–4). Pure core (PR #95), audio-paced live mode + ingestion
(tool/Settings/store/App-Intent/paste, PR #96), Share Extension (PR #98), and vision/OCR
capture (this PR) are all on `main`. Device-pending only: live streaming-recognition
behaviour, the share-sheet selection flow, and on-glasses camera scan — same posture as the
rest of the display work. Optional remaining: a Document-RAG source adapter (deferred — the
RAG store exposes semantic passages, not clean full-document text).

A hands-free teleprompter: your script shows on the in-lens HUD a window at a time, and it
**keeps your place by listening to what you actually say** — advancing as you speak. Voice
("next/back/pause") and an adjustable-WPM auto-scroll ride alongside as controls/fallbacks.
Works on the Ray-Ban Display today and pairs naturally with the
[EVEN backend](even-display-backend.md) (a teleprompter is EVEN's own flagship feature).

**Priorities (per direction):** **audio-paced first**, **vision (camera/OCR) capture
second**, scripts come from **anywhere text lives** (Apple Note / paste / Shortcut), and
**prompting speed is adjustable live**.

## What we enable
- Load a script from **anywhere text comes from** — paste/typed, the **Share Sheet**, or a
  **Shortcut / App Intent** (so an **Apple Note**, Reminder, or file flows straight in).
  Camera **OCR ("vision") capture is the second source**; Document-RAG optional.
- HUD shows a legible window with the **current line emphasized**; a progress cue ("42%").
- **Audio-paced (primary mode):** the window auto-advances to track your spoken position,
  tolerant of paraphrasing, skips, repeats, and pauses.
- **Adjustable speed, live:** WPM for auto-scroll; lead/responsiveness for audio-paced; nudge
  **"faster" / "slower"** by voice or a Settings slider.
- **Voice** control: "next / back / pause / resume / restart" (`HUDVoiceCommand`).
- Owns the display while active (suppresses ambient AI/caption producers, like a task card).

## How the user interacts
1. Bring a script in (Share an Apple Note to OpenGlasses, paste it, or a Shortcut hands it
   over), then "Start teleprompter".
2. The opening window appears on the HUD; the active line is emphasized.
3. As you speak, the window advances to keep the active line a touch ahead of your voice.
   Lose your place → "back"; need a beat → "pause"; going too fast/slow → "faster"/"slower".
   Finish → it clears and reports.

## Architecture — the seam
A `TeleprompterService` that produces `HUDScreen` frames and registers as an **interactive
presentation**, so it owns the display (reusing the same ambient-suppression gate task cards
use in `HUDRouter`). Pacing is pluggable; the audio pacer is the primary strategy.

```swift
@MainActor final class TeleprompterService: ObservableObject {
    func start(_ script: TeleprompterScript, mode: PacingMode) async
    func advance(); func back(); func pause(); func resume(); func stop()
    func setSpeed(wpm: Int)         // auto-scroll pace
    func nudgeSpeed(_ delta: Int)   // "faster"/"slower", any mode
    func setLead(lines: Int)        // how far ahead of the voice the active line sits
    var currentScreen: HUDScreen { get }   // mirrored on-phone via HUDMirrorView
}
enum PacingMode { case audioPaced, voice, autoScroll }   // speed is a separate, live setting
```

## Model (SDK-free, the deterministic core)
- `TeleprompterScript` — title + ordered `[ScriptToken]` (word + normalized form +
  line/paragraph index), built by a pure tokenizer.
- `TeleprompterPaginator` — given the cursor word-index + display geometry (600×600 Ray-Ban /
  576×288 EVEN), returns the visible window of lines with the active line marked. Reuses the
  existing 120/40-char condensing + "paginate, don't scroll" model.
- `ScriptAligner` — **the heart of audio pacing.** Takes a rolling buffer of recognized
  tokens + the current cursor; finds the best match of the recognized tail within a bounded
  forward look-ahead (small look-back) using normalized-token + fuzzy distance (the same
  fuzzy-match idea as `StudyAnswerMatcher`); returns the new cursor. Never jumps backward
  without strong evidence; holds on silence / ad-libs. Pure function → heavily tested.
- `PacingSpeed` — WPM + lead-lines + a responsiveness factor; mutable live.

## Script ingestion (text from anywhere; Apple Note is the motivating case)
iOS has **no public API to read Apple Notes** directly, so ingestion is pull-to-us, not
reach-in:
- **Share Sheet** — user shares a note's (or any) text → OpenGlasses share handling → new
  script. The clean, no-friction path for "use this note".
- **App Intent** — `AddTeleprompterScriptIntent` takes a text parameter, so a **Shortcut**
  can chain *Find Notes / Reminders / Files → OpenGlasses: Add Script*. (Note: per the
  AppShortcut-String constraint, a free-form String can't live in a *spoken* AppShortcut
  phrase — but it's fine as an **App Intent parameter invoked from the Shortcuts app**, which
  is exactly this path.)
- **Paste / typed** — trivial, the v1 default.
- **Document-RAG** — optional source for already-imported docs; not the primary route.
- **Vision (second):** point the camera at a printed/written script → `OCRService` +
  multi-page scan (reuse the Study-Mode scan pattern) → script.

## Flow
```
script in (share / intent / paste / OCR) → tokenizer → TeleprompterScript
start(audioPaced):
  SpeechRecognizer stream → ScriptAligner.advance(cursor, recognizedTail)
  "faster"/"slower"/slider → PacingSpeed (lead/responsiveness)
on cursor change → TeleprompterPaginator.window(cursor) → HUDScreen
              → GlassesDisplayService (interactive presentation; ambient suppressed)
              → HUDMirrorView reflects it on phone (device-less validation)
```

## Files
New (`OpenGlasses/Sources/Services/Teleprompter/`):
- `TeleprompterScript.swift` — model + pure tokenizer.
- `TeleprompterPaginator.swift` — cursor + geometry → `HUDScreen` window.
- `ScriptAligner.swift` — recognized-token stream → cursor (pure, the tested core).
- `PacingSpeed.swift` — WPM / lead / responsiveness, live-adjustable.
- `TeleprompterService.swift` — orchestration, pacing modes, presentation lifecycle.
- `TeleprompterScriptStore.swift` — persist saved scripts.

New tool / intents / UI:
- `NativeTools/TeleprompterTool.swift` — `teleprompter` (start/stop/next/back, faster/slower,
  pick script).
- `Intents/AddTeleprompterScriptIntent.swift` — App Intent (text param) for Shortcuts import.
- Share-Sheet text handling → "Save as teleprompter script".
- `Views/TeleprompterSettingsView.swift` — manage scripts, pick mode, **speed slider**, lead.

Touch:
- `GlassesDisplayService.swift` — interactive-presentation hook for a long-lived owner (or
  reuse `HUDRouter`'s suppression path).
- `HUDVoiceCommand.swift` — add "faster / slower" to the vocabulary.
- `NativeToolRegistry.swift` — register the tool; description into **both** prompt builders
  (`LLMService` + `GeminiLiveSessionManager`) per CLAUDE.md.
- `Config.swift` — default pacing mode, WPM, lead, font-size hint.

## Build order (deterministic core first; audio the headline; vision second)
1. **Pure core** — `TeleprompterScript` tokenizer + `ScriptAligner` + `TeleprompterPaginator`
   + `PacingSpeed`, exhaustively tested (no UI, no hardware). This *is* the audio-paced brain.
2. **Audio-paced mode (the headline)** — wire the live `SpeechRecognizer` stream into
   `ScriptAligner`; `HUDScreen` rendering + on-phone `HUDMirrorView`; live speed
   (voice "faster/slower" + slider). Voice next/back/pause + adjustable-WPM auto-scroll ride
   alongside. (Streaming-recognition behaviour is device-pending; the aligner is proven in 1.)
3. **Ingestion** — `teleprompter` tool + Settings + `TeleprompterScriptStore`; **Share Sheet**
   + **`AddTeleprompterScriptIntent`** (Apple Notes / Reminders / Files via Shortcuts) + paste.
4. **Vision capture (second)** ✅ — `teleprompter` tool `scan` action + Settings "Capture from
   camera": glasses camera → `OCRService` multi-page scan → buffer → `start`/`save`, mirroring
   the Study-Mode scan pattern (OCR is an injectable seam, so the flow is unit-tested). The
   **Document-RAG source adapter is now built**: `teleprompter` tool `start` with
   `document=<name>` pulls a saved doc's text via a new `DocumentStore.fullText` +
   `DocumentReconstructor` (de-overlaps the chunker's overlapping chunks, then re-flows one
   sentence per line for the paginator) — pure and unit-tested.

## Tests
- Tokenizer: punctuation/case/number normalization; line/paragraph indices.
- `ScriptAligner` (priority): in-order speech advances; **paraphrase** within tolerance;
  **skipped line** jumps forward; **repeated word** doesn't double-advance; **long pause**
  holds; **off-script ad-lib** holds rather than jumping; end-of-script; no spurious backward
  jumps.
- `PacingSpeed`: WPM change re-times auto-scroll; `nudgeSpeed` faster/slower clamps to bounds;
  lead change shifts the audio-paced window without losing the cursor.
- Paginator: window contents + active-line marking at 600×600 and 576×288; long-line wrap;
  progress cue.
- Ingestion: App-Intent text → script; shared text → script; OCR'd pages → script.
- Service: mode switching; presentation suppresses ambient producers and restores on stop;
  voice next/back/pause/faster/slower map correctly.

## Open questions / decisions needed
- **Lead distance** default (how far ahead of the spoken word the active line sits; ~1 line).
- **Recognition source** — reuse the wake-word `SpeechRecognizer` vs a dedicated dictation
  session; glasses vs phone mic (ties into the iOS 26 LE-Audio routing work).
- **Apple Notes** — confirmed pull-only (Share Sheet + Shortcut/App Intent); no direct read.
- **Backend** — Ray-Ban Display now; EVEN a natural second target if that backend lands.
- Not gated behind `agentModeEnabled` — display/accessibility feature, own setting.

## Dependencies / prereqs
- Existing: `GlassesDisplayService` render queue + interactive gate, `HUDScreen` DSL,
  `HUDVoiceCommand`, `HUDMirrorView`, the `SFSpeechRecognizer` stack, `StudyAnswerMatcher`
  (fuzzy-match reference), `OCRService` (vision capture). App Intents/Share already used
  elsewhere. **No new SPM dependency.**

## Why this matters
A teleprompter is a high-clarity, broadly-useful flagship for the HUD — and the audio-paced
mode is a genuine "smart glasses earn their display" moment a phone can't match. It's cheap:
the hard part (speech-to-script alignment) is a pure, fully-testable function, and it reuses
the entire display + voice + speech stack already shipped. Bonus: it's the exact feature EVEN
ships first, so it doubles as the proving vertical for a second display backend.
