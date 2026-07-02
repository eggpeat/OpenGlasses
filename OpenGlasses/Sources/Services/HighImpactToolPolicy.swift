import Foundation

/// Deterministic, **agent-mode-independent** confirmation floor for tools that take irreversible,
/// security-relevant physical actions (docs/plans/BC-unconditional-safety-gate.md).
///
/// The full `SafetySupervisor` (geofence, quiet hours, plan validation) is an agentic feature and
/// stays gated behind `Config.agentModeEnabled`. But confirmation before *unlocking a door* is a
/// user-safety floor, not an agentic feature: the audit found that with agent mode off (the
/// default) `smart_home action:unlock` executed with no confirmation, so a prompt-injected sign or
/// web result could open a lock. This policy runs regardless of agent mode.
///
/// It classifies only the narrow set of *direct-actuation* verbs on security-relevant device
/// classes. Reads, listing, and low-stakes actuation (turning a light on) pass through — the goal
/// is a floor against catastrophic actions, not a confirmation prompt on every tool call. The
/// messaging tools are already gated by their URL-scheme tap and are intentionally not duplicated
/// here.
enum HighImpactToolPolicy {

    enum Verdict: Equatable {
        case proceed
        case requiresConfirmation(summary: String)
    }

    /// Security-relevant `smart_home` (HomeKit) actions that must be confirmed. Turning a light
    /// on/off is deliberately excluded; unlocking, opening, and disarming are not.
    private static let securityActuationVerbs: Set<String> = [
        "unlock", "lock", "open", "close", "disarm", "arm",
    ]

    /// Home Assistant domains/services that actuate physical security devices. HA calls are free
    /// text, so we match on substrings of the command / service.
    private static let homeAssistantSecurityHints: [String] = [
        "unlock", "lock.", "open", "cover.", "garage", "alarm", "disarm", "arm_",
    ]

    /// Classify a tool call. Anything not explicitly matched proceeds — this is a floor, not an
    /// allowlist.
    static func evaluate(tool: String, args: [String: Any]) -> Verdict {
        switch tool {
        case "smart_home":
            let action = (args["action"] as? String)?
                .lowercased().trimmingCharacters(in: .whitespaces) ?? ""
            guard securityActuationVerbs.contains(action) else { return .proceed }
            let device = (args["device"] as? String).map { " (\($0))" } ?? ""
            return .requiresConfirmation(summary: "\(action.capitalized) smart-home device\(device)")

        case "home_assistant":
            let command = homeAssistantCommandText(args).lowercased()
            guard homeAssistantSecurityHints.contains(where: command.contains) else { return .proceed }
            return .requiresConfirmation(summary: "Home Assistant: \(homeAssistantCommandText(args))")

        default:
            return .proceed
        }
    }

    /// True when a tool has any actuation verb worth a floor-level confirmation — used to decide
    /// whether to consult `evaluate` at all.
    static func mayRequireConfirmation(tool: String) -> Bool {
        tool == "smart_home" || tool == "home_assistant"
    }

    private static func homeAssistantCommandText(_ args: [String: Any]) -> String {
        if let text = args["text"] as? String, !text.isEmpty { return text }
        if let service = args["service"] as? String, !service.isEmpty {
            let entity = (args["entity_id"] as? String).map { " \($0)" } ?? ""
            return service + entity
        }
        return args.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
