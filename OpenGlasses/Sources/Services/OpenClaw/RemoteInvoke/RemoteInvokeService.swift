import Foundation

/// Thrown by executor closures when the app services they capture have gone away.
enum RemoteInvokeError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Device services unavailable" }
}

/// One audited remote-invoke exchange (Plan BH). Persisted as a small ring so the user can
/// inspect exactly what a gateway agent asked for and what happened.
struct RemoteInvokeAuditEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let action: String
    let disposition: String   // "allowed" / "denied: …" / "unsupported" / "malformed" / "failed: …" / "declined"

    init(id: UUID = UUID(), timestamp: Date = Date(), action: String, disposition: String) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.disposition = disposition
    }
}

/// The remote-invoke pipeline (Plan BH): inbound gateway request frame → parse → policy →
/// (execute) → reply envelope, with every exchange audited. This is the only place the pieces
/// meet; each piece stays pure and independently tested.
///
/// Deny-by-default: with Agent Mode off the policy denies every command *before* the executor
/// is ever consulted — no code path reaches a device service, and the deny reply carries a
/// structured reason so the server-side agent can explain itself instead of retrying.
@MainActor
final class RemoteInvokeService: ObservableObject {

    /// Live config read on every frame (a toggle flipped in Settings applies immediately).
    struct Environment {
        var agentModeEnabled: @MainActor () -> Bool
        var toggles: @MainActor () -> RemoteCommandPolicy.Toggles
        var now: () -> Date
    }

    @Published private(set) var auditLog: [RemoteInvokeAuditEntry]

    private let environment: Environment
    private let executor: RemoteCommandExecutor
    private var rateState: RemoteInvokeRateState

    private static let auditKey = "remoteInvokeAuditLog"
    private static let auditLimit = 100

    init(environment: Environment, executor: RemoteCommandExecutor) {
        self.environment = environment
        self.executor = executor
        self.rateState = RemoteInvokeRateState(now: environment.now())
        self.auditLog = Self.loadAudit()
    }

    /// Handle one decoded inbound frame. Returns the reply to send, or `nil` when the frame is
    /// not a request at all (events/responses are the caller's business).
    func handleFrame(_ json: [String: Any]) async -> [String: Any]? {
        guard let request = RemoteCommandParser.parse(json) else { return nil }

        switch request.outcome {
        case .malformed(let reason):
            audit(action: "malformed", disposition: "malformed: \(reason)")
            return RemoteInvokeReply.malformed(id: request.id, reason: reason)

        case .unsupported(let action):
            audit(action: action, disposition: "unsupported")
            return RemoteInvokeReply.unsupported(id: request.id, action: action)

        case .command(let command):
            let decision = RemoteCommandPolicy.decide(
                command: command,
                agentModeEnabled: environment.agentModeEnabled(),
                toggles: environment.toggles(),
                rateState: &rateState,
                now: environment.now()
            )
            switch decision {
            case .deny(let reason):
                audit(action: command.canonicalAction, disposition: "denied: \(reason.code)")
                return RemoteInvokeReply.denied(id: request.id, reason: reason)

            case .allow:
                switch await executor.execute(command) {
                case .success(let payload):
                    audit(action: command.canonicalAction, disposition: "allowed")
                    return RemoteInvokeReply.success(id: request.id, payload: payload)
                case .declined:
                    audit(action: command.canonicalAction, disposition: "declined")
                    return RemoteInvokeReply.failure(id: request.id, message: "User declined the request")
                case .failed(let message):
                    audit(action: command.canonicalAction, disposition: "failed: \(message)")
                    return RemoteInvokeReply.failure(id: request.id, message: message)
                }
            }
        }
    }

    func clearAudit() {
        auditLog = []
        UserDefaults.standard.removeObject(forKey: Self.auditKey)
    }

    // MARK: - Private

    private func audit(action: String, disposition: String) {
        auditLog.insert(RemoteInvokeAuditEntry(action: action, disposition: disposition), at: 0)
        if auditLog.count > Self.auditLimit { auditLog = Array(auditLog.prefix(Self.auditLimit)) }
        if let data = try? JSONEncoder().encode(auditLog) {
            UserDefaults.standard.set(data, forKey: Self.auditKey)
        }
    }

    private static func loadAudit() -> [RemoteInvokeAuditEntry] {
        guard let data = UserDefaults.standard.data(forKey: auditKey),
              let entries = try? JSONDecoder().decode([RemoteInvokeAuditEntry].self, from: data) else { return [] }
        return entries
    }
}
