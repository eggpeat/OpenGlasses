# Plan AO — Audio-Session Resilience (realtime managers: no force-unwrap, graceful fallback)

**Status:** ✅ Shipped ([#114](https://github.com/straff2002/OpenGlasses/pull/114)). Both
realtime managers hardened via `AudioFormatFactory` / `AudioSessionError` /
`AudioSessionActivator`; 10 tests; Debug + Release green. Small, defensive, no behaviour change
on the happy path; no new SPM dependency. Nothing deferred.

The live-conversation audio paths — `GeminiLiveAudioManager` and `OpenAIRealtimeAudioManager` —
each **force-unwrap every `AVAudioFormat(...)` initializer** (9 across the two files) and call a
bare `try session.setActive(true)` with **no recovery path and no microphone-permission
gating**. A `nil` format is a hard crash, and `AVAudioFormat` returning `nil` is not
hypothetical: when the OS hands back an unexpected native input format — exactly what happens on
some Bluetooth / iOS 26 LE-Audio mic routes (`[[reference_dat_glasses_gotchas]]`) — the
force-unwrap traps and takes the app down mid-call. A failed `setActive` likewise throws
straight up and aborts the session with nothing to fall back to.

Meanwhile `WakeWordService` already does this correctly: explicit
`WakeWordError.microphonePermissionDenied` gating via `AVAudioApplication.requestRecordPermission()`,
`do/catch` around session configuration, and a `setActive` fallback. **This plan brings the two
realtime managers up to `WakeWordService`'s standard** — it copies a pattern already proven in
the codebase, it does not invent one.

## What we fix
- **No more hard crash on an unexpected audio format** — every `AVAudioFormat(...)` becomes a
  `guard let … else { throw }`, so a `nil` format surfaces as a typed, logged error and ends the
  session cleanly instead of trapping.
- **Graceful session activation** — if the preferred category/mode/options fail to activate
  (a route the OS won't grant), retry with a conservative `.default` configuration, then surface
  a clear error if even that fails — rather than aborting on the first throw.
- **Explicit mic-permission gating** — check (and, where appropriate, request) record permission
  before configuring the session, returning a typed `microphonePermissionDenied` instead of a
  confusing low-level `setActive` failure.
- **Clean reconfigure** — `try? session.setActive(false, options: .notifyOthersOnDeactivation)`
  before reconfiguring, so a stale active route doesn't make the new activation fail.

## Scope — exactly two files (plus a shared helper)
In scope (the gap):
- `OpenGlasses/Sources/Services/GeminiLive/GeminiLiveAudioManager.swift` — 5 force-unwrapped
  formats (capture, resample, playback), bare `setActive(true)`, no permission gate.
- `OpenGlasses/Sources/Services/OpenAIRealtime/OpenAIRealtimeAudioManager.swift` — 4
  force-unwrapped formats, bare `setActive(true)`, no permission gate.

Out of scope (already resilient — leave them):
- `WakeWordService.swift` — already gates permission + has `do/catch` + activation fallback; it
  is the **reference** for this work, not a target.
- `LiveTranslationService.swift` — already wraps `setActive` in `do/catch`; no force-unwraps.

## Architecture — the seam
A tiny shared, **pure** helper so both managers (and any future audio path) construct formats
the same safe way and emit the same typed error:

```swift
enum AudioSessionError: LocalizedError {
    case microphonePermissionDenied
    case invalidFormat(context: String)   // e.g. "capture", "resample", "playback"
    var errorDescription: String? { /* user-facing strings */ }
}

enum AudioFormatFactory {
    /// Throws .invalidFormat(context:) instead of returning nil → no force-unwrap at call sites.
    static func pcm(_ common: AVAudioCommonFormat,
                    sampleRate: Double, channels: AVAudioChannelCount,
                    interleaved: Bool, context: String) throws -> AVAudioFormat
}

enum AudioSessionActivator {
    /// Try the preferred (category, mode, options); on failure fall back to (.default);
    /// rethrow a typed error if both fail. Deactivates first to clear a stale route.
    static func activate(_ session: AVAudioSession,
                         category: AVAudioSession.Category,
                         mode: AVAudioSession.Mode,
                         options: AVAudioSession.CategoryOptions) throws
}
```

Both managers replace `AVAudioFormat(...)!` with `try AudioFormatFactory.pcm(…, context:)`, gate
on permission up front, and route session activation through `AudioSessionActivator.activate`.
Call-site behaviour on the happy path is identical; only the failure paths change.

## Files
New (`OpenGlasses/Sources/Services/Audio/`):
- `AudioSessionError.swift` — typed errors.
- `AudioFormatFactory.swift` — pure throwing format constructor.
- `AudioSessionActivator.swift` — activation with deactivate-first + `.default` fallback.

Touch:
- `GeminiLive/GeminiLiveAudioManager.swift` — replace 5 force-unwraps; gate permission; route
  activation through the activator.
- `OpenAIRealtime/OpenAIRealtimeAudioManager.swift` — same for its 4 force-unwraps.

## Build order
1. **Helpers + tests** — `AudioFormatFactory` (valid params → format; invalid → typed throw) and
   `AudioSessionError`, fully unit-tested. No device, no session.
2. **GeminiLiveAudioManager** — swap force-unwraps for `try AudioFormatFactory.pcm(…)`, add the
   permission gate, route `setActive` through `AudioSessionActivator`. Manager methods become
   `throws`; propagate to the existing session start with a logged error.
3. **OpenAIRealtimeAudioManager** — identical treatment.
4. **Activation fallback** — wire `AudioSessionActivator`'s `.default` retry (device-pending to
   tune; logic is testable around the typed-error surface).

## Tests
- `AudioFormatFactory.pcm`: standard 16 kHz/24 kHz mono Int16 succeeds; degenerate params
  (e.g. 0 channels / 0 sample rate) throw `.invalidFormat(context:)` with the right context
  string. Pure, no hardware.
- `AudioSessionError`: each case yields a non-empty, user-meaningful `errorDescription`.
- Manager error propagation: a forced format failure (inject via the factory seam) surfaces the
  typed error and tears the session down cleanly rather than trapping — asserted without a live
  session.

## Open questions / decisions needed
- **Permission UX** — gate-and-fail (return `.microphonePermissionDenied`, let the caller show
  the existing "enable mic" prompt) vs request-inline. Match whatever `WakeWordService` /
  `AppState` already present so there's one mic-permission story, not two.
- **Fallback aggressiveness** — one conservative `.default` retry is the floor; decide whether a
  second retry dropping `.allowBluetooth`/`.mixWithOthers` is worth it, or whether failing fast
  after one fallback (with a clear message) is better for a live call.
- **Shared helper vs WakeWordService** — `WakeWordService` already embodies this logic inline.
  Optional later cleanup: have it adopt `AudioSessionActivator` too, so there's a single
  activation routine. Not required for this plan (don't regress a working path).

## Why this matters
These are the **live AI conversation** audio paths — the moments a crash is most visible and
least recoverable. A force-unwrapped `AVAudioFormat` is a latent hard crash on exactly the
Bluetooth/LE-Audio routes these glasses use, and a bare `setActive` turns a transient route
hiccup into a dead session. The fix is small, has no happy-path behaviour change, adds no
dependency, and simply applies a resilience pattern the codebase already trusts in
`WakeWordService` to the two managers that skipped it — with the failure-mode logic captured in
pure, fully-tested helpers.
