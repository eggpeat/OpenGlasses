import Foundation
import UIKit
import Combine

/// Runs a HECA end to end (docs/plans/safety-assessment.md): grabs a job-site frame, calls the
/// structured-vision provider layer with the `SafetyAssessmentSchema`, decodes the rich `SafetyReport`
/// (all 13 hazards + score), and publishes the generic card via `StructuredVisionService` (card + HUD).
/// Configured by `AppState`. The LLM call is a settable `analyze` seam so the core is unit-testable.
/// Advisory only — not a certified inspection.
@MainActor
final class SafetyAssessmentService: ObservableObject {
    static let shared = SafetyAssessmentService()

    @Published private(set) var latest: SafetyReport?
    @Published private(set) var isAnalyzing = false

    let schema = SafetyAssessmentSchema()
    private weak var camera: CameraService?

    /// Where the generic result card is published — defaults to the shared service; tests inject a
    /// fresh one so they don't drive the host-app's real HUD/Wearables.
    var structuredVision: StructuredVisionService = .shared

    /// (systemPrompt, jpeg, jsonSchema, toolName) → JSON object. Set by `configure(...)`; tests inject a fake.
    var analyze: ((String, Data, [String: Any], String) async -> [String: Any]?)?

    init() {}

    func configure(camera: CameraService, llm: LLMService) {
        self.camera = camera
        self.analyze = { [weak llm] systemPrompt, imageData, jsonSchema, toolName in
            await llm?.analyzeFrameStructured(
                systemPrompt: systemPrompt,
                userText: "Assess this job-site scene for high-energy hazards.",
                imageData: imageData, jsonSchema: jsonSchema, toolName: toolName)
        }
    }

    /// Assess a specific JPEG. Decodes the report, publishes the generic card, returns the report.
    func assess(imageData: Data) async throws -> SafetyReport {
        guard let analyze else { throw StructuredVisionError.analysisFailed }
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let json = await analyze(schema.systemPrompt, imageData, schema.jsonSchema, "safety_assessment") else {
            throw StructuredVisionError.analysisFailed
        }
        let report = try schema.report(from: json)
        latest = report
        structuredVision.present(schema.card(for: report))
        return report
    }

    /// Grab the current camera frame and assess it.
    func assessCurrentFrame() async throws -> SafetyReport {
        guard let camera else { throw StructuredVisionError.noFrame }
        let data: Data
        if let frame = camera.latestFrame, let jpeg = frame.jpegData(compressionQuality: 0.7) {
            data = jpeg
        } else if let captured = try? await camera.capturePhoto() {
            data = captured
        } else {
            throw StructuredVisionError.noFrame
        }
        return try await assess(imageData: data)
    }

    /// A concise, speakable summary of a report for the tool to relay.
    static func summaryText(_ report: SafetyReport) -> String {
        var lines = [report.summary.isEmpty ? "Site assessed." : report.summary]
        if let score = report.score {
            let direct = report.present.filter { $0.controlStatus == .direct }.count
            lines.append("HECA score \(Int((score * 100).rounded()))% — \(direct)/\(report.present.count) present hazards directly controlled.")
        } else {
            lines.append("No high-energy hazards detected in view.")
        }
        for f in report.uncontrolled {
            let tag = f.controlStatus == .none ? "UNCONTROLLED" : "indirect-only"
            lines.append("\(tag): \(f.hazard.displayName)")
        }
        return lines.joined(separator: "\n")
    }
}
