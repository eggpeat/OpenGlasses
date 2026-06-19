import XCTest
@testable import OpenGlasses

/// Tests the `SafetyAssessmentSchema` adapter: rich `SafetyReport` → generic `AssessmentCard` (present
/// hazards as findings, control status → severity, score in the summary, top uncontrolled as the action),
/// plus the structured-output schema's category enum. Headless.
@MainActor
final class SafetyAssessmentSchemaTests: XCTestCase {

    private let schema = SafetyAssessmentSchema()

    func testJSONSchemaConstrainsCategoryToThirteen() {
        let props = (schema.jsonSchema["properties"] as? [String: Any])
        let assessments = props?["assessments"] as? [String: Any]
        let items = assessments?["items"] as? [String: Any]
        let itemProps = items?["properties"] as? [String: Any]
        let category = itemProps?["category"] as? [String: Any]
        let enumVals = category?["enum"] as? [String]
        XCTAssertEqual(enumVals?.count, 13)
        XCTAssertEqual(Set(enumVals ?? []), Set(HighEnergyHazard.allCases.map(\.rawValue)))
    }

    func testCardMapsPresentHazardsWithScore() throws {
        let json: [String: Any] = [
            "summary": "Trench and suspended load present.",
            "assessments": [
                ["category": "excavation", "is_present": true, "has_direct_control": false,
                 "has_indirect_control": true, "indirect_control": "tape"],
                ["category": "suspended_load", "is_present": true, "has_direct_control": true,
                 "direct_control": "rigging"]
            ]
        ]
        let card = try schema.makeCard(from: json, context: nil)
        XCTAssertEqual(card.kind, "safety_assessment")
        XCTAssertEqual(card.findings.count, 2)                          // only present hazards
        XCTAssertEqual(card.tier, .caution)                            // indirect-only worst → caution
        XCTAssertTrue(card.summary.contains("HECA score 50%"))
        XCTAssertEqual(card.recommendedAction, "Add a direct control for Trench / Excavation.")
        XCTAssertNotNil(card.disclaimer)
    }

    func testUncontrolledHighEnergyHazardIsCritical() throws {
        let json: [String: Any] = [
            "summary": "Live conductors, no control.",
            "assessments": [["category": "electrical_contact", "is_present": true,
                             "has_direct_control": false, "has_indirect_control": false]]
        ]
        let card = try schema.makeCard(from: json, context: nil)
        XCTAssertEqual(card.tier, .critical)
        XCTAssertEqual(card.findings.first?.severity, .critical)
    }

    func testNoHazardsIsOk() throws {
        let card = try schema.makeCard(from: ["summary": "Office, not a job site.", "assessments": []], context: nil)
        XCTAssertEqual(card.tier, .ok)
        XCTAssertTrue(card.findings.isEmpty)
        XCTAssertTrue(card.summary.contains("No high-energy hazards"))
    }
}
