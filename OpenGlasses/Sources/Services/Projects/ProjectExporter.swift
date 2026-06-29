import Foundation

/// Exports / imports a Project (Plan AN) — a `Persona` plus its namespace-scoped
/// documents — as a `ProjectBundle`. `@MainActor` because it reads/writes the
/// `DocumentStore` and the persona list; the serialization is the pure
/// `ProjectBundleCodec`, and re-ID-ing on import keeps it pure-testable.
@MainActor
enum ProjectExporter {

    /// Build a bundle for `persona`, reconstructing each scoped document's full text.
    static func makeBundle(persona: Persona, store: DocumentStore) -> ProjectBundle {
        let docs = store.list(namespace: persona.id).compactMap { ref -> ProjectBundle.BundledDocument? in
            guard let text = store.fullText(documentId: ref.id), !text.isEmpty else { return nil }
            return ProjectBundle.BundledDocument(name: ref.name, sourceType: ref.sourceType, text: text)
        }
        return ProjectBundle(persona: persona, documents: docs)
    }

    /// Write a bundle to a temp file for the share sheet; returns the file URL.
    static func exportFile(persona: Persona, store: DocumentStore) throws -> URL {
        let bundle = makeBundle(persona: persona, store: store)
        let data = try ProjectBundleCodec.encode(bundle)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ProjectBundleCodec.filename(for: persona))
        try data.write(to: url)
        return url
    }

    /// Import a bundle: register the persona under a **fresh id** (so it never collides
    /// with an existing one) and re-ingest its documents into that new namespace.
    /// Returns the imported persona. Pure w.r.t. ids — `newId` is injected for testing.
    @discardableResult
    static func importBundle(_ bundle: ProjectBundle,
                             into store: DocumentStore,
                             newId: String = UUID().uuidString,
                             addPersona: (Persona) -> Void = { Config.addPersona($0) }) async -> Persona {
        var persona = bundle.persona
        persona.id = newId
        addPersona(persona)
        for doc in bundle.documents {
            _ = await store.ingest(name: doc.name, text: doc.text, sourceType: doc.sourceType, namespace: newId)
        }
        return persona
    }
}
