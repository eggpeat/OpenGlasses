import Foundation

/// Hands-free notes scoped to the active Field Assist job — "what I'm in the middle of". A project
/// note is injected into the prompt while its job is active and yields when the user moves on, unlike
/// a durable user memory or a [[BrainStore]] fact. Stored in `brain.sqlite` (on-device, never synced)
/// via [[ProjectMemory]]; surfaced by [[ProjectMemoryFormatter]] when `Config.projectMemoryEnabled`.
struct ProjectNoteTool: NativeTool {
    let name = "project_note"
    let description = """
    Notes scoped to the ACTIVE field job (what you're mid-way through). 'save' records a note for \
    the current job (e.g. 'compressor swap is next', 'customer wants a quote for the condenser'); \
    it surfaces automatically on later turns while this job is active. 'list' shows the active job's \
    notes; 'clear' removes them. Requires an active Field Assist session — use for in-progress job \
    state, not durable user facts (use the memory tools for those).
    """

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": ["type": "string", "description": "save, list, or clear",
                           "enum": ["save", "list", "clear"]],
                "text": ["type": "string", "description": "On 'save': the note about the active job."],
            ],
            "required": ["action"],
        ]
    }

    func execute(args: [String: Any]) async throws -> String {
        let action = (args["action"] as? String ?? "list").lowercased()

        guard let session = FieldSessionService.shared.activeSession, session.isActive else {
            return "Project notes need an active Field Assist job. Start a session first, then I can keep track of what you're working on."
        }
        let tag = session.id
        let brain = BrainStore.shared

        switch action {
        case "save", "add", "note":
            guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return "What should I note about this job?"
            }
            brain.addProjectMemory(projectTag: tag, text: text)
            return "Noted for this job: \(text)"

        case "list", "show":
            let notes = brain.projectMemories(for: tag)
            guard !notes.isEmpty else { return "No notes yet for this job." }
            let list = notes.enumerated().map { i, n in "\(i + 1). \(n.text)" }.joined(separator: ". ")
            return "This job's notes: \(list)"

        case "clear":
            let count = brain.projectMemories(for: tag).count
            brain.clearProjectMemories(for: tag)
            return "Cleared \(count) note\(count == 1 ? "" : "s") for this job."

        default:
            return "Unknown action '\(action)'. Use: save, list, or clear."
        }
    }
}
