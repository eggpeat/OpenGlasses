---
description: Swift patterns, async/await, naming conventions, key types for DAT SDK iOS development
---

# DAT SDK Conventions (iOS) — v0.8.0

## Architecture

The SDK is organized into modules:
- **MWDATCore**: Device discovery, registration, permissions, device selectors, `DeviceSession`, device state (`deviceStateStream` / `ThermalLevel`)
- **MWDATCamera**: `Stream`, `VideoFrame`, `PhotoData`, photo capture
- **MWDATDisplay**: in-lens HUD — `Display` + view types (`FlexBox`, `Text`, `Button`, `Image`, `Icon`, `VideoPlayer`)
- **MWDATMockDevice**: `MockDeviceKit` for testing without hardware (UI-test oriented)

## Swift Patterns

- Most SDK operations are `async/await`, **but** `Stream.start()/stop()` and `Display.start()/stop()`
  are **synchronous** as of 0.8.0 (no `await`). `Display.send(_:)` / `Display.clearDisplay()` are async.
- Capabilities are managed through their `DeviceSession`: `addStream(config:)` / `addDisplay()` (and
  removal). There is no `Capability` protocol / `addCapability` (removed in 0.8.0).
- Observe streams via the `Announcer` publishers' `.listen {}` (`statePublisher`, `videoFramePublisher`,
  `photoDataPublisher`, `errorPublisher`).
- Annotate UI-updating code with `@MainActor`; never block the main thread with frame processing.
- All SDK errors conform to **`DatError`** (`LocalizedError`) with a consistent `description` (0.8.0
  unified error model). `capturePhoto(format:)` returns `Bool` (request accepted); the photo arrives on
  `photoDataPublisher` and stream errors on `errorPublisher` (`StreamError`).

## Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Entry point | `Wearables.shared` | `Wearables.shared.startRegistration()` |
| Sessions | `DeviceSession` | `Wearables.shared.createSession(deviceSelector:)` |
| Camera | `Stream` / `StreamConfiguration` | `deviceSession.addStream(config:)` |
| Selectors | `*DeviceSelector` | `AutoDeviceSelector(wearables:filter:)`, `SpecificDeviceSelector` |
| Publishers | `*Publisher` (Announcer) | `statePublisher`, `videoFramePublisher`, `errorPublisher` |

## Imports

```swift
import MWDATCore    // Registration, devices, permissions, DeviceSession, device state
import MWDATCamera  // Stream, StreamConfiguration, VideoFrame, PhotoData, photo capture
import MWDATDisplay // Display + view types (FlexBox/Text/Button/Image/Icon/VideoPlayer)
```

For testing:
```swift
import MWDATMockDevice  // MockDeviceKit, MockGlasses, MockCameraKit; pairGlasses(model:)
```

## Key Types

- `Wearables` — SDK entry point. Call `Wearables.configure()` at launch, then use `Wearables.shared`.
  Device state via `Wearables.deviceStateStream(for:)` (`DeviceState.thermalLevel`); there is no
  `DeviceStateSession` (removed in 0.7.0).
- `DeviceSession` — owns the connection; create with a device selector, then `addStream`/`addDisplay`.
- `Stream` — camera streaming session (`addStream(config:)`); `start()/stop()` are sync; `capturePhoto(format:) -> Bool`.
- `StreamConfiguration` — video codec, resolution, frame rate.
- `Display` — in-lens HUD; `send(_:)` replaces content (async), `clearDisplay()` blanks it (async),
  `start()/stop()` are sync.
- `Device.supportsDisplay()` / `DeviceType.supportsDisplay` — capability gate; `AutoDeviceSelector(wearables:filter:)`
  can constrain selection (e.g. `filter: { $0.supportsDisplay() }`).
- `DeviceType` — `.rayBanMeta`, `.oakleyMetaHSTN`, `.oakleyMetaVanguard`, `.rayBanMetaOptics`, `.metaGlasses`.
- `MockDeviceKit` — `pairGlasses(model: GlassesModel)` (throws `MockDeviceKitError`); oriented at the
  UI-test process (`MockDeviceTestClient`), not headless unit tests (`Wearables` fatals there).

## Error Handling

```swift
do {
    try Wearables.configure()
    try deviceSession.start()           // throwing, synchronous
} catch {
    // typed DatError: LocalizedError
}

// Camera errors arrive on the publisher (StreamError), not by throwing from capturePhoto:
stream.errorPublisher.listen { (error: StreamError) in /* map via CameraErrorPolicy */ }
```

Notes from the field:
- `CaptureError` (`.photo_capture_timeout` / `.photo_capture_failed`) is *declared* but not emitted by
  any public API in 0.8.0 — handle the `StreamError` cases on `errorPublisher` instead.
- **WiFi transport** (0.8.0) is transparent — no app-facing API; the SDK negotiates it.

## Links

- [iOS API Reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.8)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [GitHub Repository](https://github.com/facebook/meta-wearables-dat-ios)
