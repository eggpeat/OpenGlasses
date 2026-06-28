# Plan AL — On-Device Image Generation (offline create)

**Status: 📋 Planned.**

**Builds on:** the [`NativeTool`](../../OpenGlasses/Sources/Services/NativeTools/NativeTool.swift)/[`NativeToolRegistry`](../../OpenGlasses/Sources/Services/NativeTools/NativeToolRegistry.swift) tool surface, [`CameraService.saveToPhotoLibrary(_:)`](../../OpenGlasses/Sources/Services/CameraService.swift), the `pendingShareItem` + [`ShareSheet`](../../OpenGlasses/Sources/App/Views/ShareSheet.swift) pattern, and the on-device model-download/store patterns already used by `LocalLLMService` (MLX) and the Kokoro/SenseVoice model stores. Adds one new SPM dependency: **apple/ml-stable-diffusion** (Core ML, Neural Engine).

**Strategic fit:** the **only on-device AI modality OpenGlasses doesn't have**. Text, vision, voice (TTS + ASR), and RAG all run locally; image *creation* does not. It's fully offline (matches the local-first ethos), and it's a natural fit for the standalone phone app — "make me an image" with no network. Honest scope note: glasses are an input-heavy device, so the primary surface is the **phone** (and Photos), not the lens.

**Effort:** ~4–6 days.

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
