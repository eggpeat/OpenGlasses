import Foundation

/// A note scoped to a specific project/job — "what I'm in the middle of", as opposed to a durable
/// fact (a [[BrainStore]] edge) or a preference (a user memory). Transient by design: it's injected
/// while its project is the active one and yields when the user moves on.
///
/// `projectTag` is the active `FieldSession.id`, so project memory rides the field-assist job model
/// rather than inventing its own notion of "project".
struct ProjectMemory: Identifiable, Equatable {
    let id: UUID
    let projectTag: String
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), projectTag: String, text: String, createdAt: Date) {
        self.id = id
        self.projectTag = projectTag
        self.text = text
        self.createdAt = createdAt
    }
}

/// Which project memories are eligible for injection right now: only those belonging to the active
/// project. With no active project nothing is eligible — project state must not bleed across jobs.
/// Pure; trivially tested.
enum ProjectMemoryScope {
    static func eligible(_ records: [ProjectMemory], activeProject: String?) -> [ProjectMemory] {
        guard let active = activeProject,
              !active.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return records.filter { $0.projectTag == active }
    }
}

/// Formats eligible project memories into a prompt block. Empty input → "" (no heading), so an
/// active job with no notes adds nothing. Oldest-first so the block reads as a running log.
enum ProjectMemoryFormatter {
    static func block(_ records: [ProjectMemory]) -> String {
        guard !records.isEmpty else { return "" }
        let ordered = records.sorted { $0.createdAt < $1.createdAt }
        var out = "CURRENT PROJECT (what you're mid-way through on the active job — keep it in mind):"
        for r in ordered {
            out += "\n- \(r.text)"
        }
        return out
    }
}
