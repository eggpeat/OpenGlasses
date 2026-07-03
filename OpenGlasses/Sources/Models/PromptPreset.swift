import Foundation

/// A saved system prompt preset.
struct PromptPreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var prompt: String
    var isBuiltIn: Bool
    var icon: String?
    /// Suggested camera behavior for this preset mode.
    /// "smart" = auto-activate on vision queries, "always" = keep camera on, nil = default behavior.
    var cameraBehavior: String?
}
