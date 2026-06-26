import AVFoundation
import Foundation

/// Single arbiter of the shared `AVAudioSession` across the app's audio subsystems.
///
/// Subsystems `acquire` the session for a given `AudioSessionOwner` instead of calling
/// `setActive(true)` themselves, and `release` it when done. Acquiring supersedes any prior holder
/// (last-acquire-wins); releasing deactivates the session **only** if no newer owner has acquired it
/// since — the stale-release suppression that keeps a preempted subsystem's late teardown from
/// killing the session a newer one is using. The arbitration logic is the pure `AudioSessionLedger`;
/// this type adds the serial-queue safety and the real activation/deactivation.
///
/// Activation goes through `AudioSessionActivator`, so the preferred → `.default` fallback and
/// deactivate-first-to-clear-a-stale-route behaviour are unchanged.
final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()

    private let stateQueue = DispatchQueue(label: "audio.session.coordinator.state")
    private let deactivationQueue = DispatchQueue(label: "audio.session.coordinator.deactivation", qos: .userInitiated)
    private var ledger = AudioSessionLedger()

    private init() {}

    /// The owner currently recognised as holding the shared session, or `nil` if it's free.
    var currentOwner: AudioSessionOwner? {
        stateQueue.sync { ledger.current?.owner }
    }

    /// Record `owner` as the current holder **without** performing activation — for subsystems
    /// that manage their own hand-tuned session configuration (notably the always-on wake-word
    /// listener, whose `mixWithOthers` pause/resume behaviour must stay exactly as-is) but still
    /// need the coordinator to know who owns the mic. Supersedes any prior holder, just like
    /// `acquire`. Return the lease to `release` later.
    @discardableResult
    func assumeOwnership(_ owner: AudioSessionOwner) -> AudioSessionLease {
        let lease = stateQueue.sync { ledger.acquire(owner, token: UUID()).lease }
        NSLog("[AudioCoordinator] ownership assumed by %@ (self-activated)", owner.rawValue)
        return lease
    }

    /// Acquire the shared session for `owner`, configuring and activating it. Supersedes any prior
    /// holder. On activation failure the lease is rolled back (so a failed acquire never leaves the
    /// caller recorded as owner) and the error is rethrown.
    ///
    /// - Parameter configure: run after `setCategory` and before `setActive` — for non-fatal hints
    ///   like `setPreferredSampleRate` (call them with `try?` inside).
    @discardableResult
    func acquire(
        _ owner: AudioSessionOwner,
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions,
        configure: (AVAudioSession) -> Void = { _ in }
    ) throws -> AudioSessionLease {
        let token = UUID()
        let lease = stateQueue.sync { ledger.acquire(owner, token: token).lease }
        do {
            try AudioSessionActivator.activate(
                AVAudioSession.sharedInstance(),
                category: category,
                mode: mode,
                options: options,
                configure: configure
            )
            NSLog("[AudioCoordinator] acquired by %@", owner.rawValue)
            return lease
        } catch {
            // Roll the lease back if it's still ours so a failed acquire doesn't leave us "owner".
            stateQueue.sync {
                if ledger.current == lease { _ = ledger.release(lease) }
            }
            throw error
        }
    }

    /// Release `lease`. Deactivates the shared session only if `lease` is still the current owner;
    /// a stale release (a newer owner has acquired since) is ignored.
    func release(_ lease: AudioSessionLease) {
        let decision = stateQueue.sync { ledger.release(lease) }
        switch decision {
        case .deactivate:
            deactivationQueue.async {
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    NSLog("[AudioCoordinator] deactivated (released by %@)", lease.owner.rawValue)
                } catch {
                    NSLog("[AudioCoordinator] deactivate failed (%@): %@", lease.owner.rawValue, error.localizedDescription)
                }
            }
        case .superseded(let by):
            NSLog("[AudioCoordinator] stale release ignored: %@ superseded by %@", lease.owner.rawValue, by.rawValue)
        case .alreadyReleased:
            break
        }
    }
}
