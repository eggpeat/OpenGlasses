import Foundation

/// Generates the "TOOLS" prose list injected into every system prompt from the single source of
/// truth — each `NativeTool`'s own `name` + `description` (docs/plans/BG-spine-refactor.md, P1).
///
/// This block used to be maintained by hand in *two* places (`LLMService.buildSystemPrompt` and
/// `GeminiLiveSessionManager.buildSystemInstruction`), and the audit found the two copies had
/// already drifted from each other and from the real tool set. Since the machine-readable tool
/// schemas (`ToolDeclarations`) are already generated from these same descriptions, the prose is
/// now generated too — so the model's instructions can never disagree with the tools it's given.
enum SystemPromptBuilder {

    /// One "- name: description" line per tool, newest-safe (descriptions are flattened to a single
    /// line). `tools` should be the enabled (name, description) pairs in the order to present.
    static func toolLines(_ tools: [(name: String, description: String)]) -> String {
        tools
            .map { "- \($0.name): \(flatten($0.description))" }
            .joined(separator: "\n")
    }

    /// Mandatory-routing rules for tools whose domain must never be answered from the model's
    /// own weights (Plan BM P4). Returns an empty string when none of the gated tools are
    /// enabled, so the block only appears alongside the tool it mandates.
    static func routingRules(toolNames: [String]) -> String {
        var rules: [String] = []
        if toolNames.contains("health_check") {
            rules.append("""
            - Health safety is NOT answerable from your own knowledge: for ANY question about whether a \
            medication, supplement, or food is safe for the user ("can I take…", "can I eat…", drug or \
            food interactions), you MUST call health_check and base your answer on its result — it checks \
            the user's own medications, conditions, and allergies, which you cannot see.
            """)
        }
        return rules.map(flatten).joined(separator: "\n")
    }

    /// Collapse a multi-line tool description into one line so it reads as a single bullet.
    private static func flatten(_ description: String) -> String {
        description
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
