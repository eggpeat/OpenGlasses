# Plan BJ — Off-Main Audio-Session Activation (Thread Performance hang-risk)

**Status:** 📋 Planned. Deterministic seam first; the live audio behaviour is device-verified only.

## The problem
Xcode's Thread Performance Checker flags **AVAudioSession hang-risk** on the app's hottest path:
synchronous session activation on the main thread while the session is active can stall the UI
(worst on Bluetooth route changes — exactly the glasses path). Two sources:

- **`WakeWordService`** — direct `AVAudioSession.setCategory` + `setActive(true)` on the main
  thread in three methods that bypass the coordinator entirely:
  - `pauseOtherAudio` (`WakeWordService.swift:145–146`)
  - `resumeOtherAudio` (`WakeWordService.swift:176–178`)
  - `configureAudioSession` (`WakeWordService.swift:221–233`, both CarPlay and normal branches)
- **`TextToSpeechService`** — `AVAudioPlayer.play()` *implicitly* activates the session on the
  main thread (`:394`, `:417`, `:767` — the tone/thinking players).

These are hang-**risk** warnings, not crashes, and are long-standing (not a regression). They are
invisible in Release (TPC is debug-only), but the underlying block is real.

## Why the coordinator is the fix home (and the asymmetry to close)
Plan AS already built `AudioSessionCoordinator` as the single session owner. It **deactivates
off-main** (`release` → `deactivationQueue.async`, `AudioSessionCoordinator.swift:106`) but
**activates on the caller's thread**: `acquire` does the ledger bookkeeping on `stateQueue.sync`
then runs `AudioSessionActivator.activate` (setCategory → configure → setActive) inline
(`:82`). So an `acquire` from the main thread still hits `setActive` on main — and the three
WakeWordService methods above don't even use `acquire`; they touch `AVAudioSession` directly.

The fix is to make **activation** as off-main as deactivation already is, and route the direct
callers through it — **without changing the tuned category/mode/options/ordering.** Plan AS is
explicit that wake word "keeps its hand-tuned `mixWithOthers` activation and pause/resume exactly
as-is (those must not change)"; BJ moves *where* those calls run (off the main thread, preserving
order on a serial queue), never *what* they do.

## Core (this PR — deterministic, headless-testable)
- **`AudioSessionActivator`** already isolates the setCategory→configure→setActive sequence and is
  unit-testable. Add a mode that runs the sequence on a dedicated serial `activationQueue` (mirror
  of `deactivationQueue`, `qos: .userInitiated`) and completes via async/await, so ordering is
  preserved and callers `await`.
- **`AudioSessionCoordinator`**: add an async `acquireOffMain(...)` (and an async
  `reconfigure(...)` for the pause/resume category swaps) that run activation on `activationQueue`.
  Keep the existing sync `acquire` for any non-main callers. Ledger bookkeeping stays on
  `stateQueue`; the pure ownership/supersede logic is unchanged and already tested via
  `AudioSessionLedger`.
- Tests (headless, no live `AVAudioSession`): activation runs on the activation queue not the
  caller's; ordering (setCategory before setActive) preserved; a failed activation still rolls the
  lease back (existing invariant); category/mode/options are passed through verbatim (guards the
  "must not change" contract with a recorded-args spy).

## Wiring (thin edge — device-verified)
- `WakeWordService.pauseOtherAudio` / `resumeOtherAudio` / `configureAudioSession` become `async`
  and route their category+activation through the coordinator's off-main path with the **identical**
  category/mode/options they use today. Callers in `AppState`'s voice flow `await` them (the flow is
  already `async`). The synchronous `session.currentRoute`/`overrideOutputAudioPort` reads that
  follow stay after the awaited activation completes, so ordering is unchanged.
- `TextToSpeechService`: ensure the session is already active (coordinator owns it) before
  `AVAudioPlayer.play()`, so `play()` no longer triggers an implicit main-thread activation. The
  players themselves stay on the main actor (they're cheap); only activation moves.

## Scope / non-goals
- **No behaviour change** to categories, options, modes, mix/duck semantics, or pause/resume
  sequencing — BJ is a threading move only. The hand-tuned glasses/iPhone routing stays byte-for-byte.
- Out: any change to the realtime managers' activation (already coordinator owners), or new audio
  features.

## Verification
- Headless: the activator/coordinator seam tests above + full suite green.
- **On-glasses smoke test (required before merge):** wake word start, tap-to-talk, TTS playback,
  the pause-and-resume-other-audio flow (music playing → ask → resumes), a Bluetooth route change
  (glasses connect/disconnect mid-session), and confirm the TPC hang-risk warnings are gone with no
  audible/latency regression. Cannot be validated without Ray-Ban hardware.

## Sequencing
Independent of BH/BI. Natural continuation of the AO/AP/AS audio-resilience line; reuses the
`AudioSessionCoordinator`/`AudioSessionActivator`/`AudioSessionLedger` seam with no new dependency.
