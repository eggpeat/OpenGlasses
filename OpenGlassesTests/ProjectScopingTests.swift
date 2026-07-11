import XCTest
@testable import OpenGlasses

final class ProjectScopingTests: XCTestCase {

    // MARK: - ProjectScope (pure)

    func testShouldAdvertiseKB() {
        XCTAssertFalse(ProjectScope.shouldAdvertiseKB(documentCount: 0))
        XCTAssertTrue(ProjectScope.shouldAdvertiseKB(documentCount: 1))
        XCTAssertTrue(ProjectScope.shouldAdvertiseKB(documentCount: 9))
    }

    func testKnowledgeHintNilWhenEmpty() {
        XCTAssertNil(ProjectScope.knowledgeHint(projectName: "Spanish Tutor", documentCount: 0))
    }

    func testKnowledgeHintMentionsProjectAndCount() throws {
        let hint = try XCTUnwrap(ProjectScope.knowledgeHint(projectName: "Spanish Tutor", documentCount: 3))
        XCTAssertTrue(hint.contains("Spanish Tutor"))
        XCTAssertTrue(hint.contains("3 saved documents"))
        // Singular grammar at one document.
        let one = ProjectScope.knowledgeHint(projectName: "X", documentCount: 1)
        XCTAssertTrue(one?.contains("1 saved document.") ?? false)
    }

    // MARK: - ConversationThread tagging + legacy decode

    func testThreadEncodesPersonaId() throws {
        var thread = ConversationThread(mode: "voice", personaId: "proj-1")
        thread.title = "Tagged"
        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(ConversationThread.self, from: data)
        XCTAssertEqual(decoded.personaId, "proj-1")
    }

    func testLegacyThreadJSONWithoutPersonaIdDecodesToNil() throws {
        // A thread persisted before Plan AN has no `personaId` key.
        let legacy = """
        {
            "id": "abc",
            "title": "Old chat",
            "messages": [],
            "createdAt": 0,
            "updatedAt": 0,
            "mode": "voice"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ConversationThread.self, from: legacy)
        XCTAssertNil(decoded.personaId)
        XCTAssertEqual(decoded.mode, "voice")
    }

    // MARK: - ConversationStore.threads(forPersona:)

    @MainActor
    func testThreadsForPersonaFilters() {
        let store = ConversationStore()
        var a = ConversationThread(mode: "voice", personaId: "A")
        a.title = "a"
        var b = ConversationThread(mode: "voice", personaId: "B")
        b.title = "b"
        let legacy = ConversationThread(mode: "voice")   // personaId == nil
        store.threads = [a, b, legacy]

        XCTAssertEqual(store.threads(forPersona: "A").map(\.personaId), ["A"])
        XCTAssertEqual(store.threads(forPersona: "B").count, 1)
        XCTAssertEqual(store.threads(forPersona: "missing").count, 0)
        // nil ⇒ all threads (the "All" view).
        XCTAssertEqual(store.threads(forPersona: nil).count, 3)
    }

    // MARK: - DocumentStore namespace isolation

    @MainActor
    private func makeStore() -> DocumentStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return DocumentStore(directory: dir)
    }

    private let body = """
    To reset the thermostat, hold the power button for ten seconds until the screen blinks.
    The unit will then restart and return to factory defaults. For Wi-Fi setup, open the app.
    """

    @MainActor
    func testDocumentsAreIsolatedByNamespace() async throws {
        let store = makeStore()
        _ = await store.ingest(name: "ProjA Doc", text: body, namespace: "projA")
        _ = await store.ingest(name: "Global Doc", text: body, namespace: "global")
        _ = await store.ingest(name: "ProjA Doc 2", text: body, namespace: "projA")

        XCTAssertEqual(store.documentCount(namespace: "projA"), 2)
        XCTAssertEqual(store.documentCount(namespace: "global"), 1)
        XCTAssertEqual(store.documentCount(namespace: "projB"), 0)

        XCTAssertEqual(Set(store.list(namespace: "projA").map(\.name)), ["ProjA Doc", "ProjA Doc 2"])
        XCTAssertEqual(store.list(namespace: "global").map(\.name), ["Global Doc"])
        XCTAssertTrue(store.list(namespace: "projB").isEmpty)
        // Unscoped list still sees everything.
        XCTAssertEqual(store.list().count, 3)
    }

    @MainActor
    func testQueryIsScopedToNamespace() async throws {
        try XCTSkipUnless(Embedder().isAvailable, "No NLEmbedding model available in this environment")
        let store = makeStore()
        _ = await store.ingest(name: "ProjA Manual", text: body, namespace: "projA")
        _ = await store.ingest(name: "Global Manual", text: body, namespace: "global")

        let projA = store.query("how do I reset the thermostat", limit: 3, namespace: "projA")
        XCTAssertFalse(projA.isEmpty)
        XCTAssertTrue(projA.allSatisfy { $0.documentName == "ProjA Manual" })

        let projB = store.query("how do I reset the thermostat", limit: 3, namespace: "projB")
        XCTAssertTrue(projB.isEmpty, "An empty namespace returns no passages")
    }

    // MARK: - Cross-store isolation (Plan BM P8): global never sees project docs

    /// The teleprompter reaches a document by name; that lookup must not cross into another
    /// project's namespace. Deterministic (name resolution only — no embedder needed).
    @MainActor
    func testDocumentByNameHonoursNamespaceScope() async throws {
        let store = makeStore()
        _ = await store.ingest(name: "Keynote", text: body, namespace: "projA")

        // A global (or projB) chat cannot resolve projA's document by name…
        XCTAssertNil(store.document(named: "Keynote", namespaces: ["global"]))
        XCTAssertNil(store.document(named: "Keynote", namespaces: ["global", "projB"]))
        // …but its own project (plus shared global) can.
        XCTAssertEqual(store.document(named: "Keynote", namespaces: ["global", "projA"])?.name, "Keynote")
    }

    /// Semantic memory search restricted to an explicit namespace set must never return a memory
    /// from a namespace outside that set (persona isolation). Keyword fallback ⇒ no embedder needed.
    @MainActor
    func testMemorySearchNeverCrossesPersonas() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let memory = SemanticMemoryStore(directory: dir)

        memory.activePersonaId = nil
        _ = memory.remember("shared fact", value: "the office coffee is excellent")
        memory.activePersonaId = "personaA"
        _ = memory.remember("alpha fact", value: "alpha widget schematic")
        memory.activePersonaId = "personaB"
        _ = memory.remember("beta fact", value: "beta gadget blueprint")
        memory.activePersonaId = nil

        // personaA's scope (global + personaA) sees global + its own, never personaB.
        let scoped = memory.semanticSearch(query: "gadget blueprint coffee widget", limit: 10,
                                           namespaces: ["global", "personaA"])
        let values = scoped.map(\.value)
        XCTAssertTrue(values.contains("the office coffee is excellent"), "projects see global memory")
        XCTAssertTrue(values.contains("alpha widget schematic"), "a persona sees its own memory")
        XCTAssertFalse(values.contains("beta gadget blueprint"), "must not cross into another persona")

        // personaB's scope reaches personaB's memory — proving isolation, not disappearance.
        let bScope = memory.semanticSearch(query: "gadget blueprint", limit: 10,
                                           namespaces: ["global", "personaB"])
        XCTAssertTrue(bScope.map(\.value).contains("beta gadget blueprint"))
    }

    /// End-to-end through BrainTool: an unscoped/global `brain ask` must not surface a project's
    /// remembered fact, while the same ask inside that project does. Guards the tool wiring, not
    /// just the store seam. Keyword fallback ⇒ deterministic without an embedder.
    @MainActor
    func testBrainAskMemoryIsProjectScoped() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let memory = SemanticMemoryStore(directory: dir)
        memory.activePersonaId = "projA"
        _ = memory.remember("launch plan", value: "quokka launch codenamed thunderbird")
        memory.activePersonaId = nil

        var globalBrain = BrainTool()
        globalBrain.memoryStore = memory
        globalBrain.activeNamespace = { "global" }
        let globalAnswer = try await globalBrain.execute(args: ["action": "query", "question": "thunderbird launch"])
        XCTAssertFalse(globalAnswer.contains("thunderbird"),
                       "a global brain ask must not see projA's remembered fact")

        var projectBrain = BrainTool()
        projectBrain.memoryStore = memory
        projectBrain.activeNamespace = { "projA" }
        let projectAnswer = try await projectBrain.execute(args: ["action": "query", "question": "thunderbird launch"])
        XCTAssertTrue(projectAnswer.contains("thunderbird"),
                      "inside projA the same fact is visible")
    }

    /// The standalone `memory_search` tool must honour the same project scope as `brain` — a
    /// global chat can't read another persona's memory through it.
    @MainActor
    func testMemorySearchToolIsProjectScoped() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let memory = SemanticMemoryStore(directory: dir)
        memory.activePersonaId = "projA"
        _ = memory.remember("mascot", value: "the projA mascot is a narwhal")
        memory.activePersonaId = nil

        var globalSearch = MemorySearchTool()
        globalSearch.memoryStore = memory
        globalSearch.activeNamespace = { "global" }
        let globalResult = try await globalSearch.execute(args: ["query": "narwhal mascot"])
        XCTAssertFalse(globalResult.contains("narwhal"),
                       "memory_search in a global chat must not surface projA's memory")

        var projectSearch = MemorySearchTool()
        projectSearch.memoryStore = memory
        projectSearch.activeNamespace = { "projA" }
        let projectResult = try await projectSearch.execute(args: ["query": "narwhal mascot"])
        XCTAssertTrue(projectResult.contains("narwhal"), "inside projA the memory is searchable")
    }
}
