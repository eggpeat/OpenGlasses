import Foundation

/// A persona bundles a wake word, AI model, and system prompt.
/// Multiple personas can be active simultaneously — each wake word routes to its own model+prompt.
struct Persona: Codable, Identifiable, Equatable {
    var id: String
    var name: String                      // "Claude", "Jarvis", "Computer"
    var wakePhrase: String                // "hey claude"
    var alternativeWakePhrases: [String]   // ["hey cloud", "hey claud"]
    var modelId: String                   // References ModelConfig.id
    var presetId: String                  // References PromptPreset.id
    var enabled: Bool
    /// SF Symbol icon name for display in persona picker / mode cards.
    var icon: String?
    /// Whether this is a built-in preset persona (shipped with the app).
    var isBuiltIn: Bool?

    // MARK: - Agentic Capabilities (optional)

    /// Custom soul.md content for this persona. When set, overrides the global soul.
    var soulOverride: String?

    /// Chattiness level for this persona (nil = use global setting).
    /// Raw string matching Config.AgentChattiness: "quiet", "normal", "chatty".
    var chattinessRaw: String?

    /// Specific tools this persona can use (nil = all tools). Restrict to subset for focused agents.
    var allowedTools: [String]?

    /// Scheduled task IDs this persona owns. Tasks only run when this persona is active.
    var ownedTaskIds: [String]?

    /// All phrases this persona responds to (primary + alternatives).
    var allPhrases: [String] {
        [wakePhrase] + alternativeWakePhrases
    }
}
