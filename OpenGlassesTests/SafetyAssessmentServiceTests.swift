import XCTest
@testable import OpenGlasses

/// Tests the `SafetyAssessmentService` core (via the injectable `analyze` seam + a fresh `structuredVision`
/// presenter — no network, camera, or HUD), the summary text, and `safety_assessment` tool routing.
/// Uses fresh instances so it never drives the host app's real camera/Wearables HUD. Headless.
@MainActor
final class SafetyAssessmentServiceTests: XCTestCase {

    private let fixture: [String: Any] = [
        "summary": "Unshored trench beside a suspended load.",
        "assessments": [
            ["category": "excavation", "is_present": true, "has_direct_control": false,
             "has_indirect_control": true, "indirect_control": "tape"],
            ["category": "suspended_load", "is_present": true, "has_direct_control": true,
             "direct_control": "rigging"]
        ]
    ]

    private func makeService() -> (SafetyAssessmentService, StructuredVisionService) {
        let presenter = StructuredVisionService()     // fresh — no glassesDisplay
        let svc = SafetyAssessmentService()
        svc.structuredVision = presenter
        svc.analyze = { [fixture] _, _, _, _ in fixture }
        return (svc, presenter)
    }

    func testAssessDecodesReportAndPublishesCard() async throws {
        let (svc, presenter) = makeService()
        let report = try await svc.assess(imageData: Data())
        XCTAssertEqual(report.findings.count, 13)
        XCTAssertEqual(report.score ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(svc.latest?.score ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(presenter.latest?.kind, "safety_assessment")   // generic card published
    }

    func testAssessThrowsWhenAnalysisEmpty() async {
        let svc = SafetyAssessmentService()
        svc.structuredVision = StructuredVisionService()
        svc.analyze = { _, _, _, _ in nil }
        do { _ = try await svc.assess(imageData: Data()); XCTFail("expected analysisFailed") }
        catch StructuredVisionError.analysisFailed {} catch { XCTFail("wrong error: \(error)") }
    }

    func testSummaryTextHighlightsUncontrolled() throws {
        let report = try SafetyReport.from(json: fixture)
        let text = SafetyAssessmentService.summaryText(report)
        XCTAssertTrue(text.contains("HECA score 50%"))
        XCTAssertTrue(text.contains("indirect-only: Trench / Excavation"))
    }

    // MARK: - Tool

    func testToolMetadata() {
        let tool = SafetyAssessmentTool()
        XCTAssertEqual(tool.name, "safety_assessment")
        let props = tool.parametersSchema["properties"] as? [String: Any]
        XCTAssertNotNil(props?["action"])
    }

    func testToolLastReturnsLatestSummary() async throws {
        // Redirect the shared service's presenter to a fresh one so we don't drive the host HUD.
        SafetyAssessmentService.shared.structuredVision = StructuredVisionService()
        SafetyAssessmentService.shared.analyze = { [fixture] _, _, _, _ in fixture }
        _ = try await SafetyAssessmentService.shared.assess(imageData: Data())
        let result = try await SafetyAssessmentTool().execute(args: ["action": "last"])
        XCTAssertTrue(result.contains("HECA score 50%"))
    }
}
