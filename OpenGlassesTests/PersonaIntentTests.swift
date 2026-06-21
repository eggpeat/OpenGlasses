import XCTest
@testable import OpenGlasses

/// Pure-logic coverage for the Siri persona intent (#1) and the conversational
/// follow-up recency window (#2). The intent's `perform()` drives AppState /
/// Wearables, which a unit test must not touch — so we pin the deterministic
/// pieces: entity mapping, name resolution, and the recency predicate.
final class PersonaIntentTests: XCTestCase {

    private func makePersona(
        id: String, name: String, enabled: Bool = true
    ) -> Persona {
        Persona(
            id: id,
            name: name,
            wakePhrase: "hey \(name.lowercased())",
            alternativeWakePhrases: [],
            modelId: "model-\(id)",
            presetId: "preset-\(id)",
            enabled: enabled
        )
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "savedPersonas")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "savedPersonas")
        super.tearDown()
    }

    // MARK: - PersonaEntity mapping

    func testPersonaEntityMapsIdAndName() {
        let persona = makePersona(id: "abc123", name: "Claude")
        let entity = PersonaEntity(persona)
        XCTAssertEqual(entity.id, "abc123")
        XCTAssertEqual(entity.name, "Claude")
    }

    // MARK: - Config.persona(named:)

    func testPersonaNamedMatchesCaseInsensitively() {
        Config.setSavedPersonas([
            makePersona(id: "1", name: "Claude"),
            makePersona(id: "2", name: "Jarvis"),
        ])
        XCTAssertEqual(Config.persona(named: "claude")?.id, "1")
        XCTAssertEqual(Config.persona(named: "CLAUDE")?.id, "1")
        XCTAssertEqual(Config.persona(named: "  jarvis ")?.id, "2")
    }

    func testPersonaNamedReturnsNilForUnknownOrEmpty() {
        Config.setSavedPersonas([makePersona(id: "1", name: "Claude")])
        XCTAssertNil(Config.persona(named: "Cortana"))
        XCTAssertNil(Config.persona(named: ""))
        XCTAssertNil(Config.persona(named: "   "))
    }

    func testPersonaNamedIgnoresDisabledPersonas() {
        Config.setSavedPersonas([
            makePersona(id: "1", name: "Claude", enabled: false),
            makePersona(id: "2", name: "Jarvis", enabled: true),
        ])
        XCTAssertNil(Config.persona(named: "Claude"))
        XCTAssertEqual(Config.persona(named: "Jarvis")?.id, "2")
    }

    // MARK: - ConversationStore recency window

    func testRecencyWindowWithinReturnsTrue() {
        let now = Date(timeIntervalSince1970: 10_000)
        let last = now.addingTimeInterval(-60)  // 1 min ago
        XCTAssertTrue(ConversationStore.isWithinRecencyWindow(last, now: now, window: 300))
    }

    func testRecencyWindowOutsideReturnsFalse() {
        let now = Date(timeIntervalSince1970: 10_000)
        let last = now.addingTimeInterval(-600)  // 10 min ago
        XCTAssertFalse(ConversationStore.isWithinRecencyWindow(last, now: now, window: 300))
    }

    func testRecencyWindowBoundaryIsInclusive() {
        let now = Date(timeIntervalSince1970: 10_000)
        let last = now.addingTimeInterval(-300)  // exactly at the window edge
        XCTAssertTrue(ConversationStore.isWithinRecencyWindow(last, now: now, window: 300))
    }
}
