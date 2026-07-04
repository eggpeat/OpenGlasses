import Foundation

/// A simple token bucket for per-class remote-command rate limiting (Plan BH). Pure — time is
/// passed in, never read.
struct TokenBucket: Equatable {
    let capacity: Double
    let refillPerSecond: Double
    private(set) var tokens: Double
    private(set) var lastRefill: Date

    init(capacity: Double, refillPerSecond: Double, now: Date) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
        self.lastRefill = now
    }

    /// Take one token if available. Refills lazily from elapsed time, capped at `capacity`.
    mutating func tryConsume(now: Date) -> Bool {
        let elapsed = max(0, now.timeIntervalSince(lastRefill))
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        lastRefill = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

/// Per-class token buckets for a remote-invoke session.
struct RemoteInvokeRateState: Equatable {
    private var buckets: [RemoteCommandClass: TokenBucket]

    /// Defaults: generous for reads, tight for anything that acts. Bursts are the capacity;
    /// sustained rates are the refill (per minute in the comments).
    init(now: Date) {
        buckets = [
            .observe: TokenBucket(capacity: 10, refillPerSecond: 30.0 / 60.0, now: now),  // 30/min
            .output: TokenBucket(capacity: 5, refillPerSecond: 10.0 / 60.0, now: now),    // 10/min
            .capture: TokenBucket(capacity: 2, refillPerSecond: 4.0 / 60.0, now: now),    // 4/min
            .halt: TokenBucket(capacity: 5, refillPerSecond: 10.0 / 60.0, now: now),      // 10/min
        ]
    }

    mutating func tryConsume(_ commandClass: RemoteCommandClass, now: Date) -> Bool {
        guard var bucket = buckets[commandClass] else { return false }
        let allowed = bucket.tryConsume(now: now)
        buckets[commandClass] = bucket
        return allowed
    }
}

/// Pure allow/deny decision for a remote command (Plan BH). Deny-by-default:
/// - Agent Mode off denies everything (house rule for all gateway/autonomous features).
/// - Each consent class has a user toggle; `capture` defaults OFF.
/// - `halt` commands bypass the class toggles — a remote agent may always *stop* activity —
///   but are still rate-limited.
enum RemoteCommandPolicy {

    struct Toggles: Equatable {
        var observe: Bool
        var output: Bool
        var capture: Bool

        static let defaults = Toggles(observe: true, output: true, capture: false)
    }

    enum DenyReason: Equatable {
        case agentModeOff
        case classDisabled(RemoteCommandClass)
        case rateLimited(RemoteCommandClass)

        /// Structured code for the reply envelope, so the server-side agent can explain itself
        /// instead of retrying.
        var code: String {
            switch self {
            case .agentModeOff: return "denied.agent_mode_off"
            case .classDisabled(let c): return "denied.class_disabled.\(c.rawValue)"
            case .rateLimited(let c): return "denied.rate_limited.\(c.rawValue)"
            }
        }

        var message: String {
            switch self {
            case .agentModeOff:
                return "Agent Mode is off on this device; remote invoke is disabled."
            case .classDisabled(let c):
                return "The user has not enabled remote \(c.rawValue) commands."
            case .rateLimited(let c):
                return "Rate limit exceeded for \(c.rawValue) commands; slow down."
            }
        }
    }

    enum Decision: Equatable {
        case allow
        case deny(DenyReason)
    }

    static func decide(
        command: RemoteGlassesCommand,
        agentModeEnabled: Bool,
        toggles: Toggles,
        rateState: inout RemoteInvokeRateState,
        now: Date
    ) -> Decision {
        guard agentModeEnabled else { return .deny(.agentModeOff) }

        let commandClass = command.commandClass
        switch commandClass {
        case .observe where !toggles.observe: return .deny(.classDisabled(.observe))
        case .output where !toggles.output: return .deny(.classDisabled(.output))
        case .capture where !toggles.capture: return .deny(.classDisabled(.capture))
        default: break
        }

        guard rateState.tryConsume(commandClass, now: now) else {
            return .deny(.rateLimited(commandClass))
        }
        return .allow
    }
}
