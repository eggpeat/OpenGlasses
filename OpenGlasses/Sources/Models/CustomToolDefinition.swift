import Foundation

/// A user-defined tool that maps to a Siri Shortcut or URL scheme.
struct CustomToolDefinition: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String
    var parameters: [CustomToolParam]
    var actionType: ActionType
    var shortcutName: String?
    var urlTemplate: String?

    enum ActionType: String, Codable, CaseIterable {
        case shortcut
        case urlScheme

        var displayName: String {
            switch self {
            case .shortcut: return "Siri Shortcut"
            case .urlScheme: return "URL Scheme"
            }
        }
    }

    struct CustomToolParam: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var type: String  // "string" or "number"
        var description: String
        var required: Bool
    }
}
