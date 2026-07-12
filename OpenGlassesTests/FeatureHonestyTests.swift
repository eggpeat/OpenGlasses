import XCTest
import UIKit
@testable import OpenGlasses

/// BK P6 — feature-claim honesty. The "Send" tools only open a pre-filled compose screen (they
/// can't send automatically), and `fitness_coach check_form` was a hardcoded deflection that never
/// ran the built `PoseAnalyzer`. These verify the descriptions are honest and that `check_form`
/// now actually analyses a frame.
@MainActor
final class FeatureHonestyTests: XCTestCase {

    // MARK: - "Send" tool descriptions no longer overpromise

    func testSendMessageDescriptionDoesNotClaimAutoSend() {
        let d = SendMessageTool().description
        XCTAssertTrue(d.contains("review"), d)
        XCTAssertTrue(d.lowercased().contains("cannot send automatically"), d)
        XCTAssertFalse(d.hasPrefix("Send "), "must not claim it sends: \(d)")
    }

    func testSendViaDescriptionDoesNotClaimAutoSend() {
        let d = MultiChannelMessageTool().description
        XCTAssertTrue(d.contains("pre-filled"), d)
        XCTAssertTrue(d.lowercased().contains("cannot send automatically"), d)
        XCTAssertFalse(d.hasPrefix("Send "), "must not claim it sends: \(d)")
    }

    // MARK: - check_form actually runs PoseAnalyzer

    func testCheckFormWithoutFrameGivesHonestGuidanceNotDeflection() async throws {
        let tool = FitnessCoachingTool()   // no frameProvider ⇒ no camera view
        let reply = try await tool.execute(args: ["action": "check_form", "exercise": "squats"])
        XCTAssertTrue(reply.contains("squats"), reply)
        XCTAssertFalse(reply.contains("Form checking requires a camera frame"),
                       "must not return the old hardcoded deflection")
    }

    func testCheckFormWithFrameRunsPoseAnalyzer() async throws {
        var tool = FitnessCoachingTool()
        let frame = Self.solidImage()   // a plain image with no person in it
        tool.frameProvider = { frame }

        let reply = try await tool.execute(args: ["action": "check_form", "exercise": "push-ups"])
        // The whole point: check_form now runs PoseAnalyzer on the frame instead of returning the
        // old hardcoded deflection. A person-free frame resolves to a genuine Vision outcome —
        // "No body pose detected", "Couldn't process", or (in the simulator, where body-pose
        // estimation isn't available) "Pose analysis failed" — all of which prove the wire is live.
        XCTAssertFalse(reply.contains("Form checking requires a camera frame"),
                       "check_form must now run PoseAnalyzer, not deflect: \(reply)")
        XCTAssertTrue(
            ["No body pose detected", "Couldn't process", "Pose analysis", "pose"].contains { reply.contains($0) },
            "expected a PoseAnalyzer result, got: \(reply)")
    }

    private static func solidImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
    }
}
