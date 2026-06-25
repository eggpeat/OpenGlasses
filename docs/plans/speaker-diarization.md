# Plan — Speaker Diarization (Deepgram "who said what")

**Status:** 📋 Planned (not built). The deterministic core (response parsing, speaker
registry, segment merging) is fully headless-testable; only the live WebSocket stream +
mic audio are device-pending — same posture as the rest of the speech work. Closes the
long-standing gap noted in `CLAUDE.md` ("Speaker Diarization — NOT YET DONE (needs Deepgram
integration)").

Today every transcript — live ambient captions, recorded-meeting `.m4a` transcripts,
meeting summaries — is an undifferentiated wall of text. Diarization labels **who** said
each line, so captions show speaker chips, meeting transcripts read as a dialogue, and the
brain's social memory can attribute facts/action items to people.

**Priorities (per direction):** **cloud Deepgram streaming first** (live, diarized), **batch
diarization of recorded files second**, gated behind an explicit Settings opt-in + API key,
and **graceful fallback to the existing on-device `SFSpeechRecognizer`** (no labels) when no
key is set or the network is down — so nothing regresses for users who don't opt in.

## What we enable
- **Live diarized captions** — `AmbientCaptionService` shows "Speaker 1 / Speaker 2 …" (or
  named) chips on the phone and, optionally, the in-lens HUD.
- **Diarized meeting transcripts** — `AudioRecordingService` / `MeetingAssistantService`
  produce a speaker-attributed transcript (`.txt`) alongside the recording.
- **Attributed summaries & brain** — `meeting_summary` action items read "Alice to send the
  deck"; diarized turns feed `BrainStore.ingest(subject:)` so social memory knows who said
  what.
- **Name the speakers** — map the anonymous `Speaker N` ids to real names (one-tap, or via
  Face Recognition / voice over time) through a `SpeakerRegistry`.

## How the user interacts
1. Settings → **Diarization**: toggle on, paste a **Deepgram API key** (stored in the
   Keychain, like the Anthropic key). Off by default — it sends audio to a cloud service.
2. Start ambient captions or record a meeting as usual; lines now carry a speaker chip.
3. Tap a chip → "Name this speaker" (Alice). Future turns from that voice show the name.
4. No key / offline → captions and transcripts work exactly as today (single, unlabeled
   stream via `SFSpeechRecognizer`).

## Architecture — the seam
A `DiarizationProvider` protocol so the caption/recording paths are **source-agnostic**:
the existing `SFSpeechRecognizer` is a single-speaker provider; Deepgram is the diarized one.
The live service consumes the **shared audio engine** buffers (the same
`WakeWordService.addAudioBufferConsumer` fan-out `AmbientCaptionService` already uses), so no
second mic session. Pluggable, exactly like the teleprompter's pacer.

```swift
protocol DiarizationProvider: AnyObject {
    var segments: AnyPublisher<DiarizedSegment, Never> { get }  // interim + final
    func start() ; func stop()
}

@MainActor final class DeepgramSTTService: ObservableObject, DiarizationProvider {
    // URLSessionWebSocketTask to Deepgram; PCM in, JSON out → DiarizedSegment.
    func start() ; func stop()
    func sendAudio(_ buffer: AVAudioPCMBuffer)   // float32 → linear16, fed by the shared engine
}
```

## Model (SDK-free, the deterministic core)
- `DiarizedSegment` — `text`, `speaker: Int?`, `isFinal: Bool`, `start`/`end` times,
  `confidence`. Pure value type.
- `DeepgramResponseParser` — **the tested core.** Deepgram JSON → `DiarizedSegment`. Computes
  the **majority speaker across the segment's words** (handles a speaker switching
  mid-segment), distinguishes interim vs `is_final`, tolerates missing `speaker` fields. Pure
  function → heavily tested.
- `SpeakerRegistry` — stable `Int` id → optional name + a deterministic display colour;
  persists names; merges ids when two are named the same. Pure + persisted.
- `SpeakerSegmentMerger` — coalesces consecutive same-speaker finals into readable turns for
  the transcript/summary view. Pure.

## Audio
The shared engine taps `inputNode.outputFormat(forBus: 0)` (device-native, typically 48 kHz
float32). Convert to **linear16** mono at that sample rate and open the Deepgram socket with
`encoding=linear16&sample_rate=<sr>&channels=1&diarize=true&smart_format=true&interim_results=true&model=<…>`.
Conversion (float32 → Int16, downmix to mono) is a small pure helper → unit-tested on a
synthetic buffer.

## Flow
```
shared audio engine (WakeWordService) ──auto consumer──► DeepgramSTTService
   PCM(float32) → linear16 → WebSocket ──► Deepgram (diarize) ──► JSON
   JSON → DeepgramResponseParser → DiarizedSegment(speaker, text, isFinal)
        → SpeakerRegistry (id → name/colour)
        → AmbientCaptionService (chips)  +  AudioRecordingService (labeled .txt)
        → MeetingAssistant / meeting_summary (attribution)  +  BrainStore.ingest(subject:)
no key / offline → SFSpeechRecognizer provider (today's single unlabeled stream)
```

## Files
New (`OpenGlasses/Sources/Services/Diarization/`):
- `DiarizationModels.swift` — `DiarizedSegment`, `SpeakerLabel`, + `DeepgramResponseParser`.
- `SpeakerRegistry.swift` — id → name/colour, persisted.
- `SpeakerSegmentMerger.swift` — same-speaker turn coalescing.
- `DiarizationProvider.swift` — protocol + the `SFSpeechRecognizer` single-speaker adapter.
- `DeepgramSTTService.swift` — streaming WS provider (live).
- `DeepgramBatchService.swift` — upload a recorded `.m4a` for batch diarization (recordings).
- `PCMConverter.swift` — float32 buffer → linear16 mono (pure).

Touch:
- `AmbientCaptionService.swift` — consume `DiarizedSegment`; add `speaker` to `CaptionEntry`;
  render chips (provider chosen by Config).
- `AudioRecordingService.swift` / `MeetingAssistantService.swift` — write a speaker-labeled
  transcript; batch-diarize the saved file when streaming wasn't used.
- `NativeTools/MeetingSummaryTool.swift` — attribute action items; keep `BrainStore.ingest`.
- `Config.swift` — Deepgram key (Keychain), `diarizationEnabled`, model choice.
- `Views/SettingsView.swift` (+ a small `DiarizationSettingsView`) — toggle, key field, model
  picker, "name speakers" list.
- `Brain/BrainStore.swift` — ingest diarized turns with `subject:` = speaker name.

## Build order (deterministic core first; streaming the headline; batch second)
1. **Pure core** — `DiarizedSegment` + `DeepgramResponseParser` + `SpeakerRegistry` +
   `SpeakerSegmentMerger` + `PCMConverter`, exhaustively tested (no network, no mic). This is
   the diarization brain.
2. **Live streaming** — `DeepgramSTTService` on the shared engine; `DiarizationProvider`
   switch in `AmbientCaptionService`; speaker chips on phone (+ optional HUD). Fallback to
   `SFSpeechRecognizer` when no key/offline. (WebSocket behaviour device-pending; the parser
   is proven in 1.)
3. **Batch + transcripts** — `DeepgramBatchService` diarizes recorded `.m4a`; labeled
   meeting `.txt`; `meeting_summary` attribution; brain ingest by speaker.
4. **Speaker naming** — name chips; persist; optional cross-link to Face Recognition / the
   brain's people so a voice maps to a known person over time.

## Tests
- Parser (priority): single vs multi-word segments; **majority speaker** across words;
  **mid-segment speaker switch**; interim vs `is_final`; missing `speaker` field; empty
  results; punctuation/`smart_format`.
- `SpeakerRegistry`: stable ids; naming; colour determinism; merge-on-same-name.
- `SpeakerSegmentMerger`: consecutive same-speaker finals coalesce; speaker change splits.
- `PCMConverter`: float32 → Int16 range/clipping; downmix; sample-rate metadata.
- Provider fallback: no key → `SFSpeechRecognizer` adapter emits unlabeled segments
  (`speaker == nil`) and nothing else changes.

## Open questions / decisions needed
- **Model** — `nova-3` (latest, best diarization) vs a meeting-tuned variant; default + a
  picker. Confirm cost (streaming charges per minute) and document it.
- **Privacy / egress** — this **sends raw audio to Deepgram's cloud**, a real departure from
  OpenGlasses' on-device-first posture (on-device OCR, privacy filter). So: **off by default**,
  explicit opt-in with a clear disclosure, never auto-enabled. **HIPAA mode** (`Config.hipaaMode`,
  the medical recording path) must **hard-disable** cloud diarization (or gate behind a
  separate, explicit medical-data consent) — do not silently ship clinical audio off-device.
  Tie into the existing egress/consent screen (Plan R) if applicable.
- **Backgrounding** — Deepgram is cloud, so unlike on-device MLX it *can* run backgrounded
  (good for meeting capture); confirm against `[[project_local_model_background]]`.
- **Key storage** — Keychain (`KeychainService`), like the Anthropic key. Not `@AppStorage`.
- **Gating** — its own setting + key; **not** `agentModeEnabled` (it's a transcription
  enhancement, not a gateway/autonomous feature).
- **Speaker↔person linking** — manual naming v1; auto-link to Face Recognition / brain people
  is a later refinement (voice-print matching is out of scope).

## Dependencies / prereqs
- A **Deepgram account + API key** (user-provided).
- Existing: the shared audio engine (`WakeWordService.addAudioBufferConsumer`),
  `AmbientCaptionService`, `AudioRecordingService` / `MeetingAssistantService`,
  `KeychainService`, `BrainStore`, the HIPAA/medical path. **No new SPM dependency** —
  `URLSessionWebSocketTask` for streaming, `URLSession` upload for batch.

## Why this matters
Diarization is the missing layer under three features OpenGlasses already ships — ambient
captions, recorded meetings, and the brain's social memory. "Who said what" turns a
transcript into a usable record (assign action items, recall who proposed what, brief on a
person from real quotes). It's cheap and low-risk: the hard part (response → labeled segments)
is a pure, fully-testable function, it reuses the entire audio + caption + recording stack
already built, and it degrades cleanly to today's behaviour when off. The iOS client is written
fresh against Deepgram's documented streaming + batch API.
