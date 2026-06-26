import AVFoundation
import Foundation

/// The recovery action a realtime audio manager should take in response to an OS audio event.
///
/// Pure value type so the decision is unit-testable without a live `AVAudioEngine`/`AVAudioSession`;
/// the manager is left to *execute* the action on its serial audio-lifecycle queue.
enum AudioRecoveryAction: Equatable {
    /// Nothing to do (e.g. an interruption ended that the OS doesn't want us to resume, or an
    /// event arrived while we weren't capturing).
    case none
    /// An interruption began — pause the engine and remember that we were capturing.
    case pause
    /// An interruption ended and the OS says we may resume — re-activate the session and restart
    /// the engine/player.
    case resume
    /// The hardware route changed underfoot — tear the engine graph down and re-establish it on
    /// the new route rather than running a stale, silent engine.
    case resetGraph
}

/// Maps OS audio interruptions and route changes onto a recovery action.
///
/// This is the deterministic core of "self-healing" realtime audio: given the event and whether we
/// were capturing, decide what to do. The two realtime managers (`GeminiLiveAudioManager`,
/// `OpenAIRealtimeAudioManager`) consume it; `WakeWordService` already embodies the same logic
/// inline and is left untouched.
enum AudioInterruptionPolicy {

    /// Decide how to respond to an `AVAudioSession.interruptionNotification`.
    ///
    /// - Parameters:
    ///   - type: the interruption type (`.began` / `.ended`).
    ///   - shouldResume: whether the `.ended` notification carried the `.shouldResume` option.
    ///   - isCapturing: whether the manager currently intends to be capturing.
    static func action(
        for type: AVAudioSession.InterruptionType,
        shouldResume: Bool,
        isCapturing: Bool
    ) -> AudioRecoveryAction {
        // An interruption when we aren't capturing needs no recovery.
        guard isCapturing else { return .none }
        switch type {
        case .began:
            return .pause
        case .ended:
            return shouldResume ? .resume : .none
        @unknown default:
            return .none
        }
    }

    /// Decide how to respond to an `AVAudioSession.routeChangeNotification`.
    ///
    /// A device appearing or disappearing mid-call (the glasses connecting/dropping off the
    /// Bluetooth/LE-Audio route) leaves the engine pinned to a route that no longer exists, so we
    /// rebuild the graph. Benign reasons (category/override/config tweaks) need no action.
    static func action(
        for reason: AVAudioSession.RouteChangeReason,
        isCapturing: Bool
    ) -> AudioRecoveryAction {
        guard isCapturing else { return .none }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            return .resetGraph
        default:
            return .none
        }
    }
}
