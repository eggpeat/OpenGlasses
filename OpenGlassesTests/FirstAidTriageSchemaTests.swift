import XCTest
@testable import OpenGlasses

/// Headless tests for `FirstAidTriageSchema` — the life-safety tier + recommended action are
/// computed deterministically from the reported vitals (not the model), so they're fully
/// unit-tested. Mirrors the HECA consumer's guardrail posture.
final class FirstAidTriageSchemaTests: XCTestCase {

    private let schema = FirstAidTriageSchema()

    private func card(responsive: Bool? = true, breathing: String = "normal",
                      bleeding: Bool = false, findings: [[String: Any]] = [],
                      summary: String = "casualty in view") throws -> AssessmentCard {
        var json: [String: Any] = ["breathing": breathing, "severe_bleeding": bleeding,
                                   "findings": findings, "summary": summary]
        if let responsive { json["responsive"] = responsive }
        return try schema.makeCard(from: json, context: nil)
    }

    func testNotBreathingIsCriticalCPR() throws {
        let c = try card(breathing: "absent")
        XCTAssertEqual(c.tier, .critical)
        XCTAssertTrue(c.recommendedAction?.contains("CPR") ?? false)
        XCTAssertTrue(c.findings.contains { $0.label == "Not breathing" })
    }

    func testSevereBleedingIsCriticalPressure() throws {
        let c = try card(breathing: "normal", bleeding: true)
        XCTAssertEqual(c.tier, .critical)
        XCTAssertTrue(c.recommendedAction?.lowercased().contains("pressure") ?? false)
    }

    func testUnresponsiveBreathingIsCriticalRecovery() throws {
        let c = try card(responsive: false, breathing: "normal")
        XCTAssertEqual(c.tier, .critical)
        XCTAssertTrue(c.recommendedAction?.lowercased().contains("recovery") ?? false)
    }

    func testAbnormalBreathingIsCaution() throws {
        let c = try card(breathing: "abnormal")
        XCTAssertEqual(c.tier, .caution)
        XCTAssertTrue(c.findings.contains { $0.label == "Abnormal breathing" })
    }

    func testAllNormalNoFindingsIsOK() throws {
        let c = try card()
        XCTAssertEqual(c.tier, .ok)
        XCTAssertNil(c.recommendedAction)
        XCTAssertTrue(c.findings.isEmpty)
    }

    func testModelFindingRaisesTier() throws {
        let c = try card(findings: [["label": "Open fracture, left forearm", "severity": "caution"]])
        XCTAssertEqual(c.tier, .caution)
        XCTAssertEqual(c.recommendedAction, "Call emergency services and keep monitoring the casualty.")
    }

    func testAirwayPriorityWhenBleedingAndNotBreathing() throws {
        let c = try card(breathing: "absent", bleeding: true)
        XCTAssertEqual(c.tier, .critical)
        XCTAssertTrue(c.recommendedAction?.contains("CPR") ?? false)   // breathing beats bleeding
        // Both life-safety findings are still surfaced.
        XCTAssertTrue(c.findings.contains { $0.label == "Not breathing" })
        XCTAssertTrue(c.findings.contains { $0.label == "Severe bleeding" })
    }

    func testCarriesDisclaimer() throws {
        XCTAssertEqual(try card().disclaimer, FirstAidTriageSchema.disclaimer)
    }

    func testRegisteredInRegistry() {
        let registry = AssessmentSchemaRegistry()
        registry.register(FirstAidTriageSchema())
        XCTAssertTrue(registry.contains("first_aid_triage"))
        XCTAssertNotNil(registry.schema(for: "first_aid_triage"))
    }
}
