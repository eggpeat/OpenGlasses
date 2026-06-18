import Foundation

/// One of the two speech-recognition engines OpenGlasses can transcribe through.
enum ASREngine: String, CaseIterable, Equatable {
    /// On-device SenseVoice (sherpa-onnx / ONNX-CPU) — offline, private, runs backgrounded.
    case onDevice
    /// Apple `SFSpeechRecognizer` — the historical engine; may use server-side recognition.
    case appleSpeech
}

/// The user's ASR-engine preference (Additional Capabilities #8 — the on-device SenseVoice tier).
/// Persisted as a raw string in `Config.asrEnginePreference`; drives `ASREngineSelector`.
enum ASREnginePreference: String, CaseIterable, Identifiable, Codable {
    /// Best available given what's configured — Apple Speech today, on-device once its model is present.
    case auto
    /// Prefer the on-device (offline, private) engine; fall back to Apple Speech when unavailable.
    case onDevice
    /// Always use Apple Speech.
    case appleSpeech

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .onDevice: return "On-Device (SenseVoice)"
        case .appleSpeech: return "Apple Speech"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Use Apple Speech, switching to the offline on-device recognizer once its model is downloaded."
        case .onDevice: return "Prefer the offline, private on-device recognizer. Falls back to Apple Speech when its model isn't installed."
        case .appleSpeech: return "Always use Apple's speech recognizer."
        }
    }
}

/// Pure engine-selection policy for speech recognition (Additional Capabilities #8). Given what's
/// available (Apple Speech authorized, the SenseVoice model present + binary compiled in), the user's
/// preference, and whether we're online, it produces the ordered fallback chain the transcriber walks
/// (`On-Device → Apple Speech`, or the reverse). No SDK / audio state is touched — a value computation,
/// fully unit-testable headlessly.
///
/// Mirrors `TTSEngineSelector`: `.appleSpeech` is the guaranteed terminal (always available, no model),
/// and an explicit `.onDevice` preference never silently falls back to the cloud-capable Apple engine
/// when offline.
enum ASREngineSelector {

    /// What each engine can do right now. The caller folds the live signals into these booleans.
    struct Availability: Equatable {
        /// Apple `SFSpeechRecognizer` is available + authorized.
        var appleSpeechReady: Bool
        /// SenseVoice model files present **and** the sherpa-onnx binary is compiled in.
        var onDeviceReady: Bool
        /// Network is reachable (Apple Speech can use server-side recognition; on-device never needs it).
        var online: Bool

        init(appleSpeechReady: Bool, onDeviceReady: Bool, online: Bool) {
            self.appleSpeechReady = appleSpeechReady
            self.onDeviceReady = onDeviceReady
            self.online = online
        }
    }

    /// Ordered engines to try, best-first. The first element is the chosen engine; the rest are the
    /// fallback order. `.appleSpeech` is appended as the guaranteed terminal whenever it's ready.
    static func chain(preference: ASREnginePreference, availability: Availability) -> [ASREngine] {
        var order: [ASREngine]
        switch preference {
        case .auto, .appleSpeech:
            // Cloud-capable Apple Speech first (today's behaviour); on-device is the offline fallback.
            order = [.appleSpeech, .onDevice]
        case .onDevice:
            // Explicit offline/private choice: on-device first, Apple Speech only as a last resort.
            order = [.onDevice, .appleSpeech]
        }

        // For `.auto`, prefer the **on-device** engine when we're offline — Apple Speech may need the
        // network and degrade, while SenseVoice is fully local.
        if preference == .auto, !availability.online, availability.onDeviceReady,
           let appleIdx = order.firstIndex(of: .appleSpeech),
           let onDeviceIdx = order.firstIndex(of: .onDevice),
           onDeviceIdx > appleIdx {
            order.remove(at: onDeviceIdx)
            order.insert(.onDevice, at: appleIdx)
        }

        var result = order.filter { engine in
            switch engine {
            case .appleSpeech: return availability.appleSpeechReady
            case .onDevice: return availability.onDeviceReady
            }
        }
        // Apple Speech is the terminal fallback when it's available; if neither is, the chain is empty
        // and the caller reports an error (no recognizer at all is a real, surfaced failure).
        if availability.appleSpeechReady, !result.contains(.appleSpeech) {
            result.append(.appleSpeech)
        }
        return result
    }

    /// The single engine to transcribe through — the head of `chain(...)`, or nil when nothing is
    /// available (e.g. Apple Speech unauthorized and no on-device model).
    static func select(preference: ASREnginePreference, availability: Availability) -> ASREngine? {
        chain(preference: preference, availability: availability).first
    }
}
