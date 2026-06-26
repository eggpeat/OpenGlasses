import AVFoundation
import Foundation

/// The input-selection and output-fallback decision for a realtime audio session, derived purely
/// from the currently available ports and the requested mode.
struct AudioRouteDecision: Equatable {
    /// A Bluetooth hands-free input port type (the glasses mic) to prefer, or `nil` to leave the
    /// system default input in place.
    let preferredInputPortType: AVAudioSession.Port?
    /// Whether output should be forced to the phone speaker.
    let overrideToSpeaker: Bool
    /// A user-facing message when audio had to fall back off the glasses, or `nil` when the route
    /// is good. Surfaced (logged today) so the user understands why audio moved to the phone.
    let fallbackMessage: String?
}

/// Decides how to route a realtime audio session given the available inputs and the mode.
///
/// On iOS 26 the Ray-Ban glasses ride Bluetooth LE Audio (LC3), so the glasses mic can surface as
/// `.bluetoothLE` rather than `.bluetoothHFP`, and the system default input may otherwise stay on
/// the iPhone (see `reference_dat_glasses_gotchas`). This policy actively prefers a hands-free
/// input when one is present, and falls back to the phone speaker with a clear message when it
/// isn't — instead of silently capturing nothing.
///
/// Pure and side-effect-free so it is fully unit-testable; the manager performs the actual
/// `setPreferredInput` / `overrideOutputAudioPort` calls from the returned decision.
enum AudioRoutePolicy {
    /// Bluetooth hands-free input port types that can carry the glasses mic.
    static let handsFreePorts: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothLE]

    /// - Parameters:
    ///   - availableInputs: the port types currently offered by `session.availableInputs`.
    ///   - currentRoute: the port types currently in `session.currentRoute` (inputs + outputs).
    ///   - useIPhoneMode: capturing with the iPhone mic (`.voiceChat`) rather than the glasses.
    ///   - forceSpeaker: an explicit request to use the phone speaker regardless of route.
    static func decide(
        availableInputs: [AVAudioSession.Port],
        currentRoute: [AVAudioSession.Port],
        useIPhoneMode: Bool,
        forceSpeaker: Bool
    ) -> AudioRouteDecision {
        // iPhone mode or an explicit speaker preference: phone speaker, system-default input, no
        // fallback message (this is the requested route, not a degradation).
        if useIPhoneMode || forceSpeaker {
            return AudioRouteDecision(
                preferredInputPortType: nil,
                overrideToSpeaker: true,
                fallbackMessage: nil
            )
        }

        // Glasses mode: prefer the hands-free input if one is available; keep output on it.
        if let handsFree = availableInputs.first(where: { handsFreePorts.contains($0) }) {
            return AudioRouteDecision(
                preferredInputPortType: handsFree,
                overrideToSpeaker: false,
                fallbackMessage: nil
            )
        }

        // Glasses mode but no hands-free input available: fall back to the phone and say so —
        // unless the current route somehow already carries a hands-free port (don't nag then).
        let routeHasHandsFree = currentRoute.contains { handsFreePorts.contains($0) }
        return AudioRouteDecision(
            preferredInputPortType: nil,
            overrideToSpeaker: true,
            fallbackMessage: routeHasHandsFree
                ? nil
                : "Glasses audio unavailable — using phone audio until Bluetooth reconnects."
        )
    }
}
