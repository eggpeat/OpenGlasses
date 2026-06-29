import XCTest
@testable import OpenGlasses

final class ProjectBundleTests: XCTestCase {

    private func persona(id: String, name: String) -> Persona {
        Persona(id: id, name: name, wakePhrase: "hey \(name.lowercased())",
                alternativeWakePhrases: [], modelId: "m", presetId: "p", enabled: true,
                icon: nil, isBuiltIn: nil, soulOverride: "be terse",
                chattinessRaw: nil, allowedTools: nil, ownedTaskIds: nil)
    }

    // MARK: - Codec (pure)

    func testCodecRoundTrip() throws {
        let bundle = ProjectBundle(
            persona: persona(id: "proj-1", name: "Spanish Tutor"),
            documents: [.init(name: "Verbs", sourceType: "text", text: "ser vs estar")])
        let data = try ProjectBundleCodec.encode(bundle)
        XCTAssertEqual(try ProjectBundleCodec.decode(data), bundle)
    }

    func testDecodeRejectsNewerVersion() throws {
        var bundle = ProjectBundle(persona: persona(id: "x", name: "X"), documents: [])
        bundle.version = ProjectBundle.currentVersion + 1
        let data = try JSONEncoder().encode(bundle)
        XCTAssertThrowsError(try ProjectBundleCodec.decode(data)) { error in
            XCTAssertEqual(error as? ProjectBundleCodec.CodecError, .unsupportedVersion(bundle.version))
        }
    }

    func testFilenameSanitised() {
        XCTAssertEqual(ProjectBundleCodec.filename(for: persona(id: "1", name: "My Project!")), "my-project.ogproject.json")
        XCTAssertEqual(ProjectBundleCodec.filename(for: persona(id: "1", name: "   ")), "project.ogproject.json")
    }

    // MARK: - Export / import over a real store

    @MainActor
    private func makeStore() -> DocumentStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return DocumentStore(directory: dir)
    }

    private let body = """
    To reset the thermostat, hold the power button for ten seconds until the screen blinks.
    The unit then restarts and returns to factory defaults; open the app for Wi-Fi setup.
    """

    @MainActor
    func testExportThenImportRoundTripsDocumentsIntoNewNamespace() async throws {
        let store = makeStore()
        let source = persona(id: "src", name: "Field Site")
        _ = await store.ingest(name: "Manual", text: body, namespace: "src")
        _ = await store.ingest(name: "Notes", text: body, namespace: "src")

        let bundle = ProjectExporter.makeBundle(persona: source, store: store)
        XCTAssertEqual(bundle.documents.count, 2)
        XCTAssertEqual(Set(bundle.documents.map(\.name)), ["Manual", "Notes"])
        XCTAssertFalse(bundle.documents.contains { $0.text.isEmpty })

        // Import into the same store under a fresh id; capture the persona via the closure.
        var added: Persona?
        let imported = await ProjectExporter.importBundle(bundle, into: store, newId: "dst", addPersona: { added = $0 })
        XCTAssertEqual(imported.id, "dst")
        XCTAssertEqual(imported.name, "Field Site")
        XCTAssertEqual(added?.id, "dst")
        // Documents re-ingested into the new namespace, originals untouched.
        XCTAssertEqual(store.documentCount(namespace: "dst"), 2)
        XCTAssertEqual(store.documentCount(namespace: "src"), 2)
    }

    @MainActor
    func testEmptyProjectExportsNoDocuments() {
        let store = makeStore()
        let bundle = ProjectExporter.makeBundle(persona: persona(id: "empty", name: "Empty"), store: store)
        XCTAssertTrue(bundle.documents.isEmpty)
        XCTAssertEqual(bundle.persona.name, "Empty")
    }
}
