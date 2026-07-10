# Plan AL — On-Device Image Generation (offline create)

**Status: 📋 Planned.**

**Builds on:** the [`NativeTool`](../../OpenGlasses/Sources/Services/NativeTools/NativeTool.swift)/[`NativeToolRegistry`](../../OpenGlasses/Sources/Services/NativeTools/NativeToolRegistry.swift) tool surface, [`CameraService.saveToPhotoLibrary(_:)`](../../OpenGlasses/Sources/Services/CameraService.swift), the `pendingShareItem` + [`ShareSheet`](../../OpenGlasses/Sources/App/Views/ShareSheet.swift) pattern, and the on-device model-download/store patterns already used by `LocalLLMService` (MLX) and the Kokoro/SenseVoice model stores. Adds one new SPM dependency: **apple/ml-stable-diffusion** (Core ML, Neural Engine).

**Strategic fit:** the **only on-device AI modality OpenGlasses doesn't have**. Text, vision, voice (TTS + ASR), and RAG all run locally; image *creation* does not. It's fully offline (matches the local-first ethos), and it's a natural fit for the standalone phone app — "make me an image" with no network. Honest scope note: glasses are an input-heavy device, so the primary surface is the **phone** (and Photos), not the lens.

**Effort:** ~4–6 days.

---

## Revision 2026-07-10 (code-verified review) — decisions pinned before build

1. **Runtime choice is an open decision — record it, don't inherit it.** Three candidates:
   (a) **apple/ml-stable-diffusion** (the draft's pick) — ANE-targeted, best perf/watt, mature
   palettized SD-1.5 checkpoints (~1 GB 6-bit), but effectively dormant since ~2024; smoke-test
   Xcode 26 compatibility before committing, and "SDXL-Turbo-class" Core ML conversions are
   scarce — treat SD-1.5-class as the realistic target. (b) **MLX diffusion** — `mlx-swift-lm` is
   already a dependency and the MLX examples ship StableDiffusion; one runtime story and reuses the
   hub download machinery, but GPU-not-ANE (hotter, more Jetsam-prone next to the LLM).
   (c) **iOS 26 `ImageCreator` (Image Playground API)** — zero download, zero dep, system-managed
   thermal/memory; stylized-only output, Apple-Intelligence devices only. A v1 on `ImageCreator`
   with SD as the power-user tier is a legitimate radically-cheaper path — if rejected, say why.
   Whichever wins, **name the exact model repo**; "SD-1.5 or SDXL-Turbo" spans a 3× size/memory
   range that drives every constraint below.
2. **`execute` returns fast.** Awaiting a 10–25 s generation inside a tool call pauses
   camera/audio streaming for its duration (`ToolCallRouter.swift:30`) and stalls Gemini Live —
   and `NativeTool` is `@MainActor`, so a synchronous pipeline call freezes the UI. The tool
   returns "generating, about 15 seconds — it'll appear on your phone" and the results sheet owns
   success/failure. The confirmation string must not claim "saved to Photos" unless auto-save is
   real (BK P6 honesty class) — decision: **no auto-save; Save is a sheet button**.
3. **Cancellation is a feature, not a nice-to-have.** ml-stable-diffusion cancels only by
   returning `false` from the progress handler — wire it to `Task.isCancelled`, define barge-in
   ("stop" mid-generate cancels), and define Regenerate as cancel-then-restart. (BK P4 found the
   MLX text path already ignores cancellation; don't add a second offender.)
4. **Download machinery: copy Kokoro, not LocalLLMService.** BK P5 found the LLM download flow's
   Cancel is a UI no-op with caller-owned Tasks; the Kokoro pattern (`KokoroModelStore` pure FS
   bookkeeping + downloader with injected seams, staging + verify + atomic install, 0-byte-stub
   rejection) is the correct template. Add disk-space preflight and a Wi-Fi/cellular gate for the
   ~1 GB fetch.
5. **Memory + thermal arbitration.** SD peaks >1.5–2 GB even palettized; `LocalLLMService` already
   documents Jetsam kills with a 2B model loaded. Rule: **one big model at a time** — generation
   refuses (spoken message) while the local LLM is loaded, `reduceMemory` pipeline config on, and
   a memory-warning unload hook. Thermal: refuse/warn at `ProcessInfo.thermalState >= .serious`
   (no thermal check exists anywhere in Sources today; diffusion would be the app's hottest
   workload).
6. **Voice-first progress.** After "make me an image," 15–25 s of silence is a regression: start
   the thinking sound, speak completion ("done — it's on your phone") via TTS, HUD line as the
   secondary surface. Mid-generation backgrounding discards the run with a spoken note on return
   (no partial-image analogue to the LLM's partial text).
7. **History/BrainStore policy.** The generated image does **not** enter `conversationHistory`
   (avoids base64 blowing the image-aware token estimator and the Anthropic 5 MB inline cap) —
   only the confirmation text does; "edit the last image" is recorded as out-of-scope v2. Ingest a
   lightweight fact (`prompt` + saved-asset ref) into `BrainStore.shared.ingest`, matching the
   MeetingSummary/SocialContext precedent. Save to a **"Generated" album**, not the "Glasses"
   album `saveToPhotoLibrary` writes today (mislabels provenance).
8. **Deterministic core + tests (was absent — house style requires it):** `ImageModelStore`
   presence/validation against a temp dir (mirror `KokoroModelStoreTests`); downloader
   enumeration/progress/cancel over injected seams; a pure `GenerationRequest` builder (prompt +
   negative + steps/seed clamping + style presets); the prompt-enhancement builder; the tool
   gating matrix (disabled / model-absent / backgrounded / already-generating → distinct spoken
   strings); and the cancellation state machine as a pure reducer. The generate call itself is
   device-edge ("tests are the gate").
9. **Corrections to the draft below:** item 8 (hand-editing system prompts) is **superseded by
   `SystemPromptBuilder`** (BG P1) — registry registration alone is sufficient; and the "pipeline
   is text-only" framing under-sells the existing `[IMAGE_CAPTURED:<base64>]` in-band channel
   (CapturePhotoTool et al.) — the side channel is still right for *generated* images (the model
   doesn't need to see its own output; base64 in history is pure cost), but that's a choice, not a
   void. Also the HUD gap is in **our DSL wrapper**, not the SDK — MWDATDisplay has an `Image`
   view type; exposing it is a wrapper decision deferred, not an impossibility.

---

## What already exists (reuse, do not rebuild)

- **Tool surface:** `NativeTool` = `{name, description, parametersSchema, execute(args:) async throws -> String}`; `NativeToolRegistry.init` injects dependencies (constructor or post-registration property). New tool follows the same pattern.
- **Save to Photos:** `CameraService.saveToPhotoLibrary(_ data: Data)` already requests `PHPhotoLibrary` add-only auth and writes to the "Glasses" album (the `NSPhotoLibraryAddUsageDescription` key is therefore already present).
- **Result presentation:** `AppState.pendingShareItem: ShareItem?` → `ShareSheet(items: [Any])` (accepts `UIImage`); `AppState.phoneCameraRequest` → `PhoneCameraView` sheet is the model for presenting a generated-image results sheet.
- **Model management:** `LocalLLMService` (HF download + progress + load/unload) and the Kokoro/SenseVoice model stores show the established "download a big model on first use, show progress, allow delete, gate behind a Settings toggle" pattern.
- **Feature gating:** `Config.agentModeEnabled` / `Config.fieldAssistActive` show the `UserDefaults`-backed toggle pattern to copy for `imageGenerationEnabled`.

## The gap

1. No image generation anywhere in the tree.
2. **The tool result pipeline is text-only.** `ToolResult` is `success(String) | failure(String)` and the LLM receives `["result": "<text>"]`. An image must be surfaced via a **side channel** (an `AppState` published value + a results sheet), not as the tool's return value.
3. **The HUD can't render images.** `GlassesDisplayService` emits a Text/Icon/`FlexBox` DSL via `display.send(view)` — no image element. In-lens output is limited to a text confirmation.

## New work

**1. SPM dependency.**
Add to `project.base.yml` `packages:` and the `OpenGlasses` target `dependencies:`:
```yaml
  ml-stable-diffusion:
    url: https://github.com/apple/ml-stable-diffusion.git
    from: "1.1.0"
```
Then `./Scripts/generate-xcodeproj.sh` (XcodeGen auto-includes new `Sources/**` files; remember `ci_scripts/Package.resolved` per [[project_xcode_cloud_resolved]]). New signed capabilities are not required, so Xcode Cloud signing is unaffected ([[project_xcode_cloud_new_target_signing]]).

**2. `ImageGenerationService` (`@MainActor`).**
`Sources/Services/ImageGen/ImageGenerationService.swift` — wraps `StableDiffusionPipeline`:
- `load()` from the model dir in Application Support; `generate(prompt:negativePrompt:steps:seed:progress:) async throws -> UIImage`.
- DPM-Solver scheduler, ~20 steps @ 512×512 for a sane speed/quality default; progressive preview via the pipeline's per-step image callback so the UI can show the image forming.
- **Foreground-only guard.** Core ML on ANE/GPU is subject to the same constraint as MLX — it must not run backgrounded ([[project_local_model_background]]). Refuse to start (or pause) generation when not active; surface a clear message. No background-task continuation.
- Resource hygiene: load on demand, unload to free memory (mirror `LocalLLMService.unloadModel`).

**3. `ImageModelStore` + download.**
`Sources/Services/ImageGen/ImageModelStore.swift` — mirrors the MLX/Kokoro model stores: download a **palettized (6-bit, ~1 GB) Core ML SD model** from its HF repo on first use, show progress, validate, allow delete. Settings entry under a new "Image Generation" section, gated behind `Config.imageGenerationEnabled` (default **off** — it's a big download).

**4. Output channel.**
`AppState.pendingGeneratedImage: GeneratedImage?` (`{image: UIImage, prompt: String}`) presented as a results sheet (mirror `phoneCameraRequest`): preview + **Save to Photos** (`cameraService.saveToPhotoLibrary`) + **Share** (`pendingShareItem`) + **Regenerate**. Present the sheet from `MainView` so it works from any tab. HUD: a text-only "🖼️ image ready on your phone" via `GlassesDisplayService.showNotification` — no in-lens image.

**5. `ImageGenerationTool` (the agent surface).**
`Sources/Services/NativeTools/ImageGenerationTool.swift`, conforms to `NativeTool`. Action `image_generate(prompt, style?, steps?)`:
- Kicks off `ImageGenerationService.generate`, sets `pendingGeneratedImage`, and **returns a textual confirmation string** (e.g. "Generated an image for '<prompt>'. It's shown on your phone and saved to Photos.") — honouring the String-only `execute` contract; the picture itself rides the side channel.
- Gated: returns a helpful error if `imageGenerationEnabled` is off or the model isn't downloaded.
- Register in `NativeToolRegistry.init` behind the gate; inject the service like other dependency-bearing tools.

**6. Optional AI prompt enhancement.**
Behind a toggle, expand the user's short prompt with the active text model before generation (call `LLMService` with an enhancement system prompt, then stop generation) — a ~1-sentence → rich-prompt upgrade. Pure prompt-builder is unit-testable; the LLM call is the only side effect.

**7. UI affordance.**
A "Create image" quick action (Quick Actions grid / Chat composer) and the tool path. Both funnel through `ImageGenerationService`.

**8. System-prompt registration.**
Add the tool description to the system prompts in **both** `LLMService.swift` and `GeminiLiveSessionManager.swift` (CLAUDE.md "Adding a New Tool" step 3).

## Build order

1. SPM dep + `ImageGenerationService` skeleton returning a stub image (proves wiring, no model).
2. `ImageModelStore` download + progress + Settings gate.
3. Real `StableDiffusionPipeline` generate + progressive preview + foreground guard.
4. `pendingGeneratedImage` results sheet (save / share / regenerate).
5. `ImageGenerationTool` + registry + system-prompt registration.
6. Prompt enhancement (optional) + quick-action affordance.
7. Full suite + **Release** build green before PR.

## Open questions

- **Which model?** *Recommendation: a small, fast palettized model (SD-1.5-class or SDXL-Turbo-class) with DPM-Solver at ~512²/~20 steps* for ~8–15 s on an A17/M-class device. SDXL-Turbo-style few-step models trade some quality for speed — worth A/B'ing.
- **Storage cap.** A ~1 GB model is user-visible and deletable; show the size before download, no silent eviction (mirror Plan O's doc-store stance).
- **Default gating.** Off by default; first use prompts the download. Keep it out of the default tool advertisement until the model is present so the LLM doesn't offer a capability that isn't there.
- **Intent auto-detect?** *Skip for v1* — explicit tool/affordance only; no heuristic "did the user mean generate vs analyze" classifier yet.
- **HUD image rendering.** Out of scope until/if the display SDK gains an image element; text confirmation only.

## Dependencies

- New SPM: `apple/ml-stable-diffusion`. A Core ML SD model (downloaded from HF at runtime). Photos add-only permission (already present). No changes to the tool-result contract — images use the `pendingGeneratedImage` side channel. Foreground-only ([[project_local_model_background]]).
