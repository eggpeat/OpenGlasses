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

    /// The on-device prompt budget (BK P2) must sit below the observed OOM point (an ~8.2k-token
    /// prompt Jetsam-killed the app) yet leave headroom for a normal lean prompt + some history —
    /// for every recommended model and for an unknown/user-typed id.
    func testOnDevicePromptBudgetIsBelowTheObservedOOMPoint() {
        let ids = LocalLLMService.recommendedModels.map(\.id) + [nil, "some/unknown-model"]
        for id in ids {
            let budget = LocalModelBudget.promptBudget(for: id)
            XCTAssertLessThan(budget, 8241,
                              "budget for \(id ?? "nil") must sit below the OOM point")
            XCTAssertGreaterThanOrEqual(budget, 2048,
                              "budget for \(id ?? "nil") must leave headroom for a lean prompt + history")
        }
    }

    func testPromptTooLongErrorIsDescriptive() {
        let msg = LocalLLMError.promptTooLong(tokens: 9000, limit: 4096).errorDescription ?? ""
        XCTAssertTrue(msg.contains("9000") && msg.contains("4096"))
        XCTAssertTrue(msg.lowercased().contains("cloud"), "tell the user the actionable fallback")
    }
}
