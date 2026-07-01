# Plan BE — Wake-Word Service Hardening

**Status:** 📋 Planned (audit round 12, priority 4)

## The problem
`WakeWordService` is the app's always-on path, and the July 2026 audit found its four worst
stability and battery findings concentrated there:

1. **Data race on the audio tap (crash risk).** The `installTap` block runs on the Core Audio
   render thread but reads `@MainActor` state: it appends to `recognitionRequest` (nil'd on the
   main actor during pause/cleanup) and iterates the `audioBufferForwarders` dictionary
   (mutated on the main actor whenever captions/rewind/recording toggle)
   (`WakeWordService.swift:548-558`, `:459-478`, `:759-765`). Torn dictionary read →
   `EXC_BAD_ACCESS` on the hottest path in the app (~40–50 calls/sec whenever listening).
2. **NotificationCenter observers accumulate forever.** `configureAudioSession()` registers
   interruption + route-change observers and discards the tokens; three code paths deliberately
   reset `audioSessionConfigured` and re-register (`:238-257`, `:93-96`, `:317-322`, `:794-796`).
   Every glasses on/off adds a pair; after N reconnects one route change fires N duplicate
   handlers, each spawning its own cleanup/restart task — compounding engine restarts and
   duplicated `startListening()` races. (`GeminiLiveAudioManager.installSessionObservers`/
   `removeObservers` is the correct in-repo pattern.)
3. **Continuous server-based recognition.** `requiresOnDeviceRecognition = false` (`:493`) means
   the always-on listener streams mic audio to Apple's servers 24/7, with restart churn at the
   ~1-min server limit. Short-phrase wake-word spotting works on-device; the accuracy trade only
   matters for real queries (`TranscriptionService`), which keep server recognition. This is the
   single largest steady battery/data drain in the app.
4. **The interruption handler fights active realtime sessions.** On interruption-ended it
   unconditionally `setActive(true)` + `startListening()` (`:263-286`), stomping a live
   Gemini/OpenAI `.videoChat` config and spinning up a second engine contending for the mic —
   bypassing the `AudioSessionCoordinator` lease model that exists to prevent exactly this
   (phone-call-during-session → garbled capture). Related: `LiveTranslationService` sets
   `.measurement` mode as a coexisting rider and never restores it — the documented
   "iPhone-speaker TTS extremely quiet" state (`LiveTranslationService.swift:83-96`).

Smaller, same file: a MainActor `Task` per audio buffer for silence checks (~45/sec, forever);
the silence-shutoff comment says ~60 s but the constant works out to ~13–38 s depending on
sample rate; `CXCallObserver` allocated per call.

## What we build
1. **Thread-safe tap handoff.** The tap block touches nothing `@MainActor`: an
   `OSAllocatedUnfairLock`-guarded (or dedicated-serial-queue-owned) snapshot of
   `(recognitionRequest, forwarders)` published by the main actor on every change; the tap reads
   the snapshot, appends, forwards. Forwarder add/remove swaps the snapshot atomically.
2. **Owned observer tokens.** Store interruption/route tokens; remove before re-adding;
   remove in deinit/stop. Mirror `GeminiLiveAudioManager`.
3. **On-device wake recognition.** `requiresOnDeviceRecognition = true` for the wake listener
   behind `Config.onDeviceWakeWordEnabled` (default **on**), with `contextualStrings` kept.
   `TranscriptionService` unchanged. Fallback: if on-device is unsupported for the locale, keep
   server mode (capability check, logged).
4. **Coordinator-aware interruption recovery.** The interruption-ended branch consults
   `AudioSessionCoordinator.currentOwner` and only reactivates + restarts listening when wake word
   is (or should become) the owner. `LiveTranslationService` drops `.measurement` or restores the
   wake-word config on stop.
5. Cheap wins: batch the silence check (accumulate RMS on the tap thread, hop on state
   *transition* only), fix the silence-window constant + comment, cache the `CXCallObserver`.

## Scope
In: the five items + tests. Out: replacing SFSpeechRecognizer as the wake engine (the SenseVoice/
alt-trigger work lives in Plan AJ), any UI change.

## Build order
1. Extract the tap-side state into a `WakeTapState` (lock-guarded snapshot) + tests
   (concurrent mutate/iterate stress test under TSAN locally).
2. Observer-token ownership + tests (register/reset/register → exactly one pair).
3. Coordinator-aware interruption branch + `LiveTranslationService` restore + ledger tests
   (the `AudioSessionLedger` test suite from Plan AS is the home).
4. On-device recognition flag + capability fallback (device-validated for wake accuracy before
   flipping the default in a release).
5. Silence-check batching + constant fix.

## Tests
Headless: snapshot swap under concurrent access; observer count invariants; ledger scenarios
(interruption during Gemini session → wake word does not steal); silence-window math. On-device
wake-word accuracy with on-device recognition is device-pending by house style.

## Why this matters
This one service is simultaneously the app's top crash risk, its top battery drain, and the source
of the "audio broke after a phone call" class of bugs. Every fix has an in-repo pattern to copy.
