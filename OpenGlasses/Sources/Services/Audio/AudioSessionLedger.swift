import Foundation

/// A subsystem that can hold the shared `AVAudioSession`.
///
/// The app has several mic/audio subsystems that each activate the one shared session; the
/// coordinator built on this ledger arbitrates them so only one is the recognised owner at a time.
/// (Adoption is incremental — the realtime managers route through the coordinator first; the
/// always-on wake-word path and the gentler coexisting services follow.)
enum AudioSessionOwner: String, Sendable, CaseIterable {
    case wakeWord
    case transcription
    case liveTranslation
    case geminiLive
    case openAIRealtime
    case expertCall
}

/// A claim on the shared session: who holds it, an opaque token identifying this exact claim, and a
/// monotonically increasing generation so a later claim always sorts after an earlier one.
struct AudioSessionLease: Equatable, Sendable {
    let owner: AudioSessionOwner
    let token: UUID
    let generation: UInt64
}

/// What the holder of a lease should do when it releases.
enum AudioSessionReleaseDecision: Equatable {
    /// This lease is still the active one — actually deactivate the shared session.
    case deactivate
    /// A different owner has since acquired the session — do nothing (a stale release must not
    /// tear the session out from under whoever holds it now). Carries the current owner.
    case superseded(by: AudioSessionOwner)
    /// Nobody holds the session — nothing to deactivate.
    case alreadyReleased
}

/// The deterministic "single owner" guarantee for the shared `AVAudioSession`, as a pure value type.
///
/// Last-acquire-wins: acquiring supersedes any prior holder and bumps the generation. The crucial
/// invariant is on **release** — a lease only deactivates the session if it is *still the current
/// lease*. That is what stops a preempted owner's late, asynchronous teardown (an interruption
/// reset, a delayed `stopCapture`) from deactivating the session a newer owner just acquired — the
/// exact race that leaves the shared session dead mid-conversation when subsystems each manage it
/// independently.
///
/// Pure and single-threaded by construction; the live `AudioSessionCoordinator` wraps it behind a
/// serial queue and performs the actual activation/deactivation.
struct AudioSessionLedger {
    /// The lease currently recognised as owning the session, or `nil` when it's free.
    private(set) var current: AudioSessionLease?
    private var generation: UInt64 = 0

    init() {}

    /// Make `owner` the current holder, superseding any previous lease.
    /// - Parameter token: an opaque identity for this claim (the coordinator passes a fresh `UUID`;
    ///   tests pass a fixed one).
    /// - Returns: the new lease, and the lease it preempted (`nil` if the session was free).
    @discardableResult
    mutating func acquire(_ owner: AudioSessionOwner, token: UUID) -> (lease: AudioSessionLease, preempted: AudioSessionLease?) {
        let preempted = current
        generation &+= 1
        let lease = AudioSessionLease(owner: owner, token: token, generation: generation)
        current = lease
        return (lease, preempted)
    }

    /// Decide what releasing `lease` should do, clearing ownership only if `lease` is still current.
    mutating func release(_ lease: AudioSessionLease) -> AudioSessionReleaseDecision {
        guard let active = current else { return .alreadyReleased }
        if active == lease {
            current = nil
            return .deactivate
        }
        return .superseded(by: active.owner)
    }
}
