import XCTest
@testable import OpenGlasses

/// Headless tests for the Plan U hero capture flow (refrigeration asset inspection): the JSON
/// decodes against the `CaptureFlow` schema and drives the `CaptureFlowRunner` end to end —
/// precondition gating, numeric range validation, and enum resolution. Mirrors the shipped
/// `Vaults/refrigeration/flows/asset_inspection_v1.json`.
@MainActor
final class CaptureFlowHeroFlowsTests: XCTestCase {

    private let assetInspectionJSON = """
    {
      "id": "asset_inspection_v1",
      "title": "Refrigeration Asset Inspection",
      "applies_to": ["refrigeration_unit", "condenser", "compressor"],
      "preconditions": [
        { "type": "inside_region", "region": "work_zone", "message": "Move inside the work zone before inspecting." }
      ],
      "steps": [
        { "field": "asset_id", "prompt": "Scan or read the asset tag.", "binding": { "type": "barcode_or_voice" }, "required": true, "completion": { "min_len": 3 } },
        { "field": "suction_pressure", "prompt": "Read the suction pressure in psig.", "binding": { "type": "voice_number", "unit": "psig" }, "required": true, "completion": { "range": [0, 400] } },
        { "field": "discharge_pressure", "prompt": "Read the discharge pressure in psig.", "binding": { "type": "voice_number", "unit": "psig" }, "required": true, "completion": { "range": [0, 600] } },
        { "field": "condition", "prompt": "Overall condition?", "binding": { "type": "enum", "options": ["good", "fair", "poor", "failed"] }, "required": true },
        { "field": "nameplate_photo", "prompt": "Photograph the nameplate.", "binding": { "type": "photo" }, "required": false }
      ]
    }
    """

    private func flow() throws -> CaptureFlow {
        try JSONDecoder().decode(CaptureFlow.self, from: Data(assetInspectionJSON.utf8))
    }

    func testHeroFlowDecodes() throws {
        let f = try flow()
        XCTAssertEqual(f.id, "asset_inspection_v1")
        XCTAssertEqual(f.steps.count, 5)
        XCTAssertEqual(f.appliesTo, ["refrigeration_unit", "condenser", "compressor"])
        XCTAssertEqual(f.steps.first?.binding.type, .barcodeOrVoice)
        XCTAssertEqual(f.steps[1].binding.type, .voiceNumber)
        XCTAssertEqual(f.steps[1].binding.unit, "psig")
        XCTAssertEqual(f.steps[3].binding.options, ["good", "fair", "poor", "failed"])
        XCTAssertEqual(f.preconditions.first?.region, "work_zone")
    }

    func testPreconditionGatesOnRegion() throws {
        let f = try flow()
        XCTAssertEqual(CaptureFlowRunner(flow: f, sessionId: "s", insideRegion: { _ in false })
            .unmetPreconditions().first?.region, "work_zone")
        XCTAssertTrue(CaptureFlowRunner(flow: f, sessionId: "s", insideRegion: { _ in true })
            .unmetPreconditions().isEmpty)
        XCTAssertTrue(CaptureFlowRunner(flow: f, sessionId: "s")   // unknown region never hard-blocks
            .unmetPreconditions().isEmpty)
    }

    func testRunnerValidatesRangeAndEnum() throws {
        let runner = CaptureFlowRunner(flow: try flow(), sessionId: "s")

        // barcode/voice
        guard case .accepted = runner.answer("AC-1024") else { return XCTFail("asset_id should accept") }
        // voice_number out of range → rejected, stays on the step
        guard case .rejected = runner.answer("999") else { return XCTFail("999 psig is out of 0–400") }
        guard case .accepted = runner.answer("120") else { return XCTFail("120 psig in range") }
        // discharge
        guard case .accepted = runner.answer("250") else { return XCTFail("discharge in range") }
        // enum: bad option rejected, valid option accepted
        guard case .rejected = runner.answer("purple") else { return XCTFail("purple isn't an option") }
        guard case .accepted = runner.answer("fair") else { return XCTFail("fair is a valid option") }

        XCTAssertEqual(runner.record.fields.first(where: { $0.field == "suction_pressure" })?.value.display.contains("120"), true)
        XCTAssertEqual(runner.record.fields.count, 4)   // asset_id, suction, discharge, condition
    }
}
