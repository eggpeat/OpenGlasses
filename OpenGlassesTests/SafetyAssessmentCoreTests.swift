import XCTest
import CoreGraphics
@testable import OpenGlasses

/// Tests for the HECA deterministic core (docs/plans/safety-assessment.md): the 13-hazard catalog,
/// the pure score, control-status derivation, `SafetyReport.from(json)` decode/validation, and the
/// pure box→rect mapping. Headless — no LLM.
final class SafetyAssessmentCoreTests: XCTestCase {

    // MARK: - Catalog

    func testCatalogIsThirteenWithStableIds() {
        XCTAssertEqual(HighEnergyHazard.allCases.count, 13)
        let ids = Set(HighEnergyHazard.allCases.map(\.rawValue))
        XCTAssertTrue(ids.isSuperset(of: ["suspended_load", "excavation", "arc_flash", "toxic_chemical_radiation"]))
        for h in HighEnergyHazard.allCases {
            XCTAssertFalse(h.displayName.isEmpty)
            XCTAssertFalse(h.energyThreshold.isEmpty)
            XCTAssertFalse(h.systemImage.isEmpty)
        }
    }

    // MARK: - Control status

    func testControlStatusDerivation() {
        XCTAssertEqual(HazardFinding(hazard: .fire, hasDirectControl: true, hasIndirectControl: true).controlStatus, .direct)
        XCTAssertEqual(HazardFinding(hazard: .fire, hasIndirectControl: true).controlStatus, .indirect)
        XCTAssertEqual(HazardFinding(hazard: .fire).controlStatus, ControlStatus.none)
    }

    // MARK: - Score

    private func report(_ findings: [HazardFinding]) -> SafetyReport {
        SafetyReport(id: "t", createdAt: Date(), summary: "", findings: findings)
    }

    func testScore() {
        // 1 of 2 present hazards directly controlled → 0.5
        let r = report([
            HazardFinding(hazard: .excavation, isPresent: true, hasIndirectControl: true),
            HazardFinding(hazard: .suspendedLoad, isPresent: true, hasDirectControl: true)
        ])
        XCTAssertEqual(r.score ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(r.topUncontrolled?.hazard, .excavation)
        XCTAssertEqual(r.uncontrolled.count, 1)
    }

    func testScoreEdgeCases() {
        XCTAssertNil(report([HazardFinding(hazard: .fire, isPresent: false)]).score)         // none present
        XCTAssertEqual(report([HazardFinding(hazard: .fire, isPresent: true, hasDirectControl: true)]).score ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(report([HazardFinding(hazard: .fire, isPresent: true)]).score ?? -1, 0.0, accuracy: 0.0001)
    }

    func testTopUncontrolledPrefersNoneOverIndirect() {
        let r = report([
            HazardFinding(hazard: .excavation, isPresent: true, hasIndirectControl: true),  // indirect
            HazardFinding(hazard: .arcFlash, isPresent: true)                                // none
        ])
        XCTAssertEqual(r.topUncontrolled?.hazard, .arcFlash)
    }

    // MARK: - Decode / validation

    private let fixture: [String: Any] = [
        "summary": "Workers near an unshored trench beside a suspended load.",
        "assessments": [
            ["category": "excavation", "is_present": true, "has_direct_control": false,
             "has_indirect_control": true, "indirect_control": "caution tape", "comments": "no trench box",
             "evidence": [["note": "open trench", "box_2d": [400, 100, 900, 500]]]],
            ["category": "suspended_load", "is_present": true, "has_direct_control": true,
             "direct_control": "certified rigging + exclusion zone", "comments": ""],
            ["category": "not_a_real_hazard", "is_present": true]   // unknown id → ignored
        ]
    ]

    func testDecodeFillsAllThirteenAndIgnoresUnknown() throws {
        let r = try SafetyReport.from(json: fixture)
        XCTAssertEqual(r.findings.count, 13)                 // always all 13
        XCTAssertEqual(r.summary, "Workers near an unshored trench beside a suspended load.")
        let exc = r.findings.first { $0.hazard == .excavation }!
        XCTAssertTrue(exc.isPresent)
        XCTAssertEqual(exc.controlStatus, .indirect)
        XCTAssertEqual(exc.evidence.first?.box, [400, 100, 900, 500])
        XCTAssertEqual(r.findings.first { $0.hazard == .suspendedLoad }?.controlStatus, .direct)
        XCTAssertEqual(r.score ?? -1, 0.5, accuracy: 0.0001)  // unknown id didn't count
    }

    // MARK: - Box mapping

    func testBoxToRect() {
        let rect = SafetyBoxMapping.rect(for: [400, 100, 900, 500], in: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(rect, CGRect(x: 100, y: 400, width: 400, height: 500))
    }

    func testBoxToNormalizedRegion() {
        let region = SafetyBoxMapping.normalizedRegion(for: [400, 100, 900, 500])
        XCTAssertEqual(region ?? [], [0.1, 0.4, 0.4, 0.5])
    }

    func testBoxMappingRejectsMalformed() {
        XCTAssertNil(SafetyBoxMapping.rect(for: [1, 2, 3], in: CGSize(width: 100, height: 100)))
        XCTAssertNil(SafetyBoxMapping.normalizedRegion(for: []))
    }
}
