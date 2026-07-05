import XCTest
@testable import OpenGlasses

/// Regression guard for the talk-button / Field-Assist crash: the on-device agent model must
/// load through the TEXT factory, not the vision factory. `visionModelIds` decides that in
/// `LocalLLMService.loadModel`, so the agent model landing in that set silently routes inference
/// into mlx-swift-lm's crashing `MLXVLM.Gemma4` (an uncatchable MLX assertion).
@MainActor
final class LocalModelRoutingTests: XCTestCase {

    func testAgentModelDoesNotLoadThroughTheVisionFactory() {
        XCTAssertFalse(
            LocalLLMService.visionModelIds.contains(Config.defaultAgentModelId),
            "the on-device agent model must load as text; listing it as a vision model routes it "
            + "to the crashing MLXVLM.Gemma4 forward pass")
    }

    func testGemma4IsTreatedAsTextNotVision() {
        // Any gemma-4 id is a text/agentic model here; the vision set is SmolVLM only.
        XCTAssertFalse(LocalLLMService.visionModelIds.contains { $0.contains("gemma-4") })
        XCTAssertTrue(LocalLLMService.visionModelIds.allSatisfy { $0.contains("SmolVLM") },
                      "only genuine VLMs belong in the vision factory route")
    }
}
