import XCTest
@testable import OpenGlasses

final class UserCorrectionDetectorTests: XCTestCase {

    // MARK: - Detector (pure)

    func testDetectsCorrections() {
        let positives = [
            "No, that's wrong",
            "that's not what I meant",
            "I meant the other one",
            "you're wrong about that",
            "that's incorrect",
            "not what I asked",
            "you misunderstood me",
        ]
        for p in positives {
            XCTAssertNotNil(UserCorrectionDetector.detect(p), "should detect: \(p)")
        }
    }

    func testIgnoresNonCorrections() {
        let negatives = [
            "no problem",
            "no thanks",
            "actually that's perfect",
            "yes please",
            "thanks, that's right",
            "I said yes to that",   // bare "i said" isn't a correction phrase
            "",
            "ok",
        ]
        for n in negatives {
            XCTAssertNil(UserCorrectionDetector.detect(n), "should NOT detect: \(n)")
        }
    }

    // MARK: - noteUserTurn wiring

    @MainActor
    private func makeStore() -> EvolvedSkillStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return EvolvedSkillStore(directory: dir)
    }

    @MainActor
    func testNoteUserTurnRecordsCorrectionWhenAgentModeOn() async {
        let key = "agentModeEnabled"
        let prior = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(prior, forKey: key) }
        UserDefaults.standard.set(true, forKey: key)

        let service = SkillEvolutionService(store: makeStore())
        await service.noteUserTurn(message: "No, that's wrong — I meant Celsius",
                                   priorPrompt: "what's 20 degrees", priorResponse: "20 degrees Fahrenheit is…")
        XCTAssertEqual(service.samples.count, 1)
        XCTAssertEqual(service.samples.first?.kind, .userCorrection)
        XCTAssertEqual(service.samples.first?.prompt, "what's 20 degrees")
    }

    @MainActor
    func testNoteUserTurnIgnoresNonCorrectionOrNoPriorAnswer() async {
        let key = "agentModeEnabled"
        let prior = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(prior, forKey: key) }
        UserDefaults.standard.set(true, forKey: key)

        let service = SkillEvolutionService(store: makeStore())
        // Not a correction → no sample.
        await service.noteUserTurn(message: "thanks!", priorPrompt: "p", priorResponse: "r")
        // A correction but no prior answer → no sample.
        await service.noteUserTurn(message: "that's wrong", priorPrompt: "p", priorResponse: "   ")
        XCTAssertTrue(service.samples.isEmpty)
    }

    @MainActor
    func testNoteUserTurnNoOpWhenAgentModeOff() async {
        let key = "agentModeEnabled"
        let prior = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(prior, forKey: key) }
        UserDefaults.standard.set(false, forKey: key)

        let service = SkillEvolutionService(store: makeStore())
        await service.noteUserTurn(message: "that's wrong", priorPrompt: "p", priorResponse: "r")
        XCTAssertTrue(service.samples.isEmpty)
    }
}
