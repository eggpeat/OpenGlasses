import XCTest
@testable import OpenGlasses

/// Headless tests for filling a `voice_number` capture-flow step from an instrument reading (Plan
/// AD × U): unit conversion to the step's unit, range validation, and rejection of incompatible units.
@MainActor
final class CaptureFlowVoiceNumberTests: XCTestCase {

    private func numberFlow(unit: String?, range: [Double]?) -> CaptureFlow {
        CaptureFlow(id: "f", title: "F", steps: [
            FlowStep(field: "gauge", prompt: "Read the gauge.",
                     binding: FieldBinding(type: .voiceNumber, unit: unit),
                     completion: range.map { Completion(minLen: nil, range: $0) })
        ])
    }

    private func reading(_ value: Double, _ unit: String, quantity: String = "pressure") -> InstrumentReading {
        InstrumentReading(quantity: quantity, value: value, unit: unit, confidence: 0.9)
    }

    // MARK: - Pure numberValue

    func testNumberValueSameUnitPassesThrough() {
        let step = numberFlow(unit: "psig", range: nil).steps[0]
        XCTAssertEqual(CaptureFlowRunner.numberValue(for: step, reading: reading(120, "psig")), 120)
        // Case-insensitive unit match.
        XCTAssertEqual(CaptureFlowRunner.numberValue(for: step, reading: reading(120, "PSIG")), 120)
    }

    func testNumberValueConvertsAcrossUnits() {
        let step = numberFlow(unit: "°C", range: nil).steps[0]
        let v = CaptureFlowRunner.numberValue(for: step, reading: reading(212, "°F", quantity: "temperature"))
        XCTAssertEqual(try XCTUnwrap(v), 100, accuracy: 0.001)   // 212 °F → 100 °C
    }

    func testNumberValueNilForIncompatibleUnits() {
        let step = numberFlow(unit: "psig", range: nil).steps[0]
        // A temperature reading can't fill a pressure step.
        XCTAssertNil(CaptureFlowRunner.numberValue(for: step, reading: reading(75, "°F", quantity: "temperature")))
    }

    func testNumberValueNoStepUnitUsesRawValue() {
        let step = numberFlow(unit: nil, range: nil).steps[0]
        XCTAssertEqual(CaptureFlowRunner.numberValue(for: step, reading: reading(42, "anything")), 42)
    }

    // MARK: - answer(reading:)

    func testAcceptsReadingInRange() {
        let runner = CaptureFlowRunner(flow: numberFlow(unit: "psig", range: [0, 600]), sessionId: "s")
        // A single-step flow completes on store, so success is `.accepted` or `.finished` — just not rejected.
        if case .rejected(let reason) = runner.answer(reading: reading(120, "psig")) {
            XCTFail("in-range reading should be stored, not rejected: \(reason)")
        }
    }

    func testAcceptedReadingAdvancesToNextStep() {
        // Two steps so the first answer returns `.accepted(next:)` rather than `.finished`.
        let flow = CaptureFlow(id: "f", title: "F", steps: [
            FlowStep(field: "gauge", prompt: "Read the gauge.",
                     binding: FieldBinding(type: .voiceNumber, unit: "psig"),
                     completion: Completion(minLen: nil, range: [0, 600])),
            FlowStep(field: "note", prompt: "Any note?", binding: FieldBinding(type: .voice))
        ])
        let runner = CaptureFlowRunner(flow: flow, sessionId: "s")
        guard case .accepted = runner.answer(reading: reading(120, "psig")) else {
            return XCTFail("expected the in-range reading to be accepted and advance")
        }
    }

    func testRejectsOutOfRangeReading() {
        let runner = CaptureFlowRunner(flow: numberFlow(unit: "psig", range: [0, 600]), sessionId: "s")
        guard case .rejected = runner.answer(reading: reading(700, "psig")) else {
            return XCTFail("expected the out-of-range reading to be rejected")
        }
    }

    func testRejectsIncompatibleUnitReading() {
        let runner = CaptureFlowRunner(flow: numberFlow(unit: "psig", range: [0, 600]), sessionId: "s")
        guard case .rejected = runner.answer(reading: reading(75, "°F", quantity: "temperature")) else {
            return XCTFail("expected the unconvertible reading to be rejected")
        }
    }

    func testRejectsWhenStepIsNotANumberStep() {
        let flow = CaptureFlow(id: "f", title: "F", steps: [
            FlowStep(field: "note", prompt: "Say a note.", binding: FieldBinding(type: .voice))
        ])
        let runner = CaptureFlowRunner(flow: flow, sessionId: "s")
        guard case .rejected = runner.answer(reading: reading(120, "psig")) else {
            return XCTFail("a non-number step should reject a meter reading")
        }
    }
}
