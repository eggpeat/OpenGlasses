import AppIntents

/// An enabled persona, exposed to Siri/Shortcuts as a selectable parameter.
///
/// Crucially, an `AppEntity` parameter (unlike a free-form `String`) IS allowed
/// inside an `AppShortcut` phrase — so "Ask Claude on OpenGlasses…" works in one
/// breath, with Siri resolving "Claude" against the user's real persona list.
struct PersonaEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Persona"
    static var defaultQuery = PersonaQuery()

    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ persona: Persona) {
        self.id = persona.id
        self.name = persona.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Enumerates the user's enabled personas for the Siri/Shortcuts parameter UI.
/// `EntityStringQuery` (not just `EntityQuery`) so Siri can resolve a *spoken*
/// persona name — "ask Claude" → the Claude persona — rather than always falling
/// back to a disambiguation list.
struct PersonaQuery: EntityStringQuery {
    func entities(for identifiers: [PersonaEntity.ID]) async throws -> [PersonaEntity] {
        Config.enabledPersonas
            .filter { identifiers.contains($0.id) }
            .map(PersonaEntity.init)
    }

    func suggestedEntities() async throws -> [PersonaEntity] {
        Config.enabledPersonas.map(PersonaEntity.init)
    }

    /// Match a spoken/typed persona name (case-insensitive substring) so Siri can
    /// resolve "ask Claude" to the Claude persona.
    func entities(matching string: String) async throws -> [PersonaEntity] {
        let target = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return [] }
        return Config.enabledPersonas
            .filter { $0.name.lowercased().contains(target) }
            .map(PersonaEntity.init)
    }
}
