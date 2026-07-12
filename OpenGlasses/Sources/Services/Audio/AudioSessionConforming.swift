import AVFoundation

/// The slice of `AVAudioSession` the activator/coordinator touch, behind a protocol seam (BJ PR1).
///
/// Before this, `AudioSessionActivator` took a concrete `AVAudioSession` and the coordinator
/// hard-wired `AVAudioSession.sharedInstance()`, so neither was unit-testable — the activation
/// order, the fallback behaviour, and the release race could only be reasoned about, never asserted.
/// A recording fake conforming to this protocol drives all of that headlessly (no live session).
///
/// `AVAudioSession` already implements every method with a matching signature, so its conformance
/// is automatic apart from the `currentRoutePortTypes` projection (the full `currentRoute`
/// description has no public initialiser, so we expose the port-type list a fake *can* construct —
/// which is all `AudioRoutePolicy` consumes anyway).
protocol AudioSessionConforming: AnyObject {
    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    func overrideOutputAudioPort(_ port: AVAudioSession.PortOverride) throws
    func setPreferredSampleRate(_ sampleRate: Double) throws
    func setPreferredIOBufferDuration(_ duration: TimeInterval) throws
    /// Input + output port types of the current route (the subset `AudioRoutePolicy` needs).
    var currentRoutePortTypes: [AVAudioSession.Port] { get }
}

extension AVAudioSession: AudioSessionConforming {
    var currentRoutePortTypes: [AVAudioSession.Port] {
        currentRoute.inputs.map(\.portType) + currentRoute.outputs.map(\.portType)
    }
}
