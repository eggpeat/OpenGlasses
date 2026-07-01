# Plan BD — Realtime Session Resilience

**Status:** 📋 Planned (audit round 12, priority 3)

## The problem
The July 2026 audit found that **every long realtime session currently dies or wedges**, and the
failure is visual-only in a voice-first app:

1. **Gemini Live `goAway` guarantees death instead of reconnect.** The server sends `goAway`
   before its session time limit — i.e. on every long session. Current handling
   (`GeminiLiveService.swift:394-401` + `GeminiLiveSessionManager.swift:178-187`) fires
   `onDisconnected` with `reconnecting == false`, so the manager calls `stopSession()` →
   `intentionalDisconnect = true`, delegate callbacks nil'd — the reconnect machinery is disarmed
   seconds before the close it exists to handle.
2. **One OpenAI Realtime server `error` event makes the assistant silently deaf forever.**
   `OpenAIRealtimeService.swift:418-423` sets `.error` with no path back to `.ready`, no
   reconnect, no teardown: `sendAudio` drops everything while `isActive` stays true, the mic tap
   keeps running, and the UI looks live. The app's own client-VAD `response.cancel` racing a
   response end triggers exactly this ("no active response to cancel").
3. **The reconnect machine stalls forever on an open-but-mute socket.** Retry is driven only by
   `onClose`/`onError`; a 15 s connect-timeout produces neither, so no next attempt is ever
   scheduled — "Reconnecting…" forever, mic held open (`GeminiLiveService.swift:186-204`,
   `OpenAIRealtimeService.swift:242-257`).
4. Supporting defects: `reconnectAttempts` never resets on a fresh session (a new session inherits
   an exhausted counter → first drop gives up instantly); the stale 15 s timeout task is never
   cancelled and can kill the *next* attempt; duplicate `scheduleReconnect` calls from
   close+error+receive-loop for one failure overwrite `reconnectTask` without cancelling
   (reconnect storms); audio lease + interruption observers leak on the failed-connect path.
5. **No voice feedback on session death** — errors surface only in `TranscriptOverlay` /
   `ConnectionBanner` / `StatusIndicator`. A user with the phone pocketed talks into a dead session
   and hears silence. (Direct mode already speaks its errors.)

Related same-theme mediums (in scope if cheap, else logged as follow-ups): OpenClawBridge handshake
has no timeout + `webSocketTask!` force-unwrap across awaits; Deepgram streaming error state is
terminal and invisible; WebRTC streamer reconnects forever at fixed 2 s with leaked URLSessions.

## What we build
### The deterministic core: `ReconnectMachine`
Both services share one pure state machine
(`Sources/Services/Realtime/ReconnectMachine.swift`):
- States: `idle / connecting(attempt) / connected / waitingRetry(attempt, deadline) / gaveUp /
  closed(intentional)`.
- Inputs: `connectRequested, connectSucceeded, connectFailed(reason), socketClosed(code),
  socketError, goAwayReceived(timeLeft), serverErrorEvent(isFatal), disconnectRequested,
  retryTimerFired`.
- Outputs (effects, returned not performed): `openSocket, closeSocket, scheduleRetry(delay),
  cancelRetry, notifyTerminal(reason)`.
- Encodes the fixes by construction: `goAway` → proactive reconnect; fatal server error →
  reconnect path, recoverable → no state change; `connectFailed` schedules the next attempt
  itself (no reliance on socket events); counters reset on `connectRequested` from `idle`;
  single retry timer (schedule cancels the old); duplicate failure inputs in one cycle coalesce.
- Table-driven tests for the full input×state matrix (this is the AudioRoutePolicy/
  AudioInterruptionPolicy pattern from Plan AP applied to sockets).

### Wiring
- `GeminiLiveService` and `OpenAIRealtimeService` route all connection events through the machine
  and execute its effects; classify OpenAI `error` events (a small pure `isFatal(errorEvent)` —
  cancellation races are recoverable); cancel the connect-timeout task in `resolveConnect`;
  release the audio lease + remove observers on failed connect.
- **Audible failure feedback:** on `notifyTerminal` (and optionally on reconnect start/success), a
  short tone or local `AVSpeechSynthesizer` phrase via the existing TTS tone path — never
  ElevenLabs (network may be the thing that's down). Session managers stop capture so the mic is
  actually released.

## Scope
In: the machine + both realtime services + audible feedback + lease/observer cleanup. Cheap
adjacent fixes (OpenClawBridge handshake deadline + `guard let`; Deepgram nil-on-error so the lazy
connect retries). Out: WebRTC streamer overhaul (Plan BE-adjacent follow-up), UI redesign of
connection state.

## Build order
1. `ReconnectMachine` + exhaustive table tests.
2. `isFatal` error-event classifier + tests (real event fixtures).
3. Gemini wiring (goAway path first — it's the every-session killer), then OpenAI.
4. Audible terminal/reconnect feedback + mic release assertions.
5. OpenClawBridge + Deepgram cheap fixes.

## Tests
Machine matrix (pure); per-service integration tests with a scripted fake socket (connect-timeout →
retry scheduled; goAway → reconnect not stopSession; fatal error event → reconnect; fresh session →
counter reset; two failure events in one cycle → one retry task). Live-network behavior is
device-pending by house style.

## Why this matters
Realtime voice is a headline mode, and today its longevity ceiling is the server's session limit —
every long conversation ends in a hard, silent death. The pure-machine shape makes the fix
regression-proof and finally testable.
