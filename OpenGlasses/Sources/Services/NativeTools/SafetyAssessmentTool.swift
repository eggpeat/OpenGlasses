import Foundation

/// `safety_assessment` — Field-Assist (B2B) HECA tool. Runs a High-Energy Control Assessment on the
/// current job-site view from the glasses camera: detects the 13 high-energy (SIF-capable) hazards and
/// whether each has a DIRECT control, and returns a summary + HECA score. Delegates to
/// `SafetyAssessmentService.shared` (which also publishes the result card + HUD). Advisory only.
@MainActor
struct SafetyAssessmentTool: NativeTool {
    let name = "safety_assessment"

    let description = """
    Run a High-Energy Control Assessment (HECA) on the current job-site view from the glasses camera — \
    detects the 13 high-energy serious-injury/fatality hazards and whether each is safeguarded by a DIRECT \
    control, and returns a summary plus a HECA score. Use for "assess this site", "is this safe?", "safety \
    check". Actions: run (assess now), last (repeat the latest result). Advisory only — verify on site; not \
    a certified inspection.
    """

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["run", "last"],
                    "description": "run a new assessment on the current view, or repeat the last result."
                ]
            ],
            "required": [] as [String]
        ]
    }

    func execute(args: [String: Any]) async throws -> String {
        let service = SafetyAssessmentService.shared
        switch (args["action"] as? String ?? "run").lowercased() {
        case "last":
            guard let report = service.latest else {
                return "No safety assessment yet. Say \"assess this site\" to run one."
            }
            return SafetyAssessmentService.summaryText(report)
        default:
            do {
                let report = try await service.assessCurrentFrame()
                return SafetyAssessmentService.summaryText(report)
            } catch StructuredVisionError.noFrame {
                return "I couldn't get a camera view of the site. Point the glasses at the work area and try again."
            } catch {
                return "Safety assessment failed: \(error.localizedDescription)"
            }
        }
    }
}
