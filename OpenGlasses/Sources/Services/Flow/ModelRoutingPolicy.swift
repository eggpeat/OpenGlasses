import Foundation

/// How a classified turn should be routed to a model (Plan BG P2).
enum ModelTurnRoute: Equatable {
    /// Use the on-device agent model (fast path).
    case localAgent
    /// Temporarily switch the active model to this tier-recommended model for the turn.
    case switchModel(toId: String)
    /// Keep the currently active model.
    case keepCurrent
}

/// Pure decision for how to route a classified turn to a model. Extracted from
/// `AppState.handleTranscription` so the branching — fast-tier agent model vs. auto-routing to a
/// tier-recommended model vs. keeping the current one — is unit-tested rather than buried in the
/// live voice path.
enum ModelRoutingPolicy {
    /// - Parameters:
    ///   - agentIsCloud: whether the configured agent model is a cloud model (vs on-device MLX).
    ///   - localAgentEnabled: user opt-in for the on-device agent (off by default; that path can crash).
    ///   - tierModelId: id of the model recommended for this tier (`Config.modelForTier(...)?.id`), if any.
    ///   - activeModelId: the currently active model id.
    static func decide(
        isFastTier: Bool,
        agentModeEnabled: Bool,
        agentModelDownloaded: Bool,
        agentIsCloud: Bool,
        localAgentEnabled: Bool,
        isPhoto: Bool,
        autoRoutingEnabled: Bool,
        tierModelId: String?,
        activeModelId: String?
    ) -> ModelTurnRoute {
        // Fast-tier queries go to the agent model when agentic mode is on and the model is ready.
        // The on-device MLX agent only runs when the user opted in (it can fatally crash); a cloud
        // agent model routes normally. Photo turns never use the agent (they need vision).
        if isFastTier, agentModeEnabled, agentModelDownloaded,
           (agentIsCloud || localAgentEnabled), !isPhoto {
            return .localAgent
        }
        // Otherwise temporarily switch to the tier-recommended model when auto-routing is on and it
        // differs from the active one.
        if autoRoutingEnabled, let tierModelId, tierModelId != activeModelId {
            return .switchModel(toId: tierModelId)
        }
        return .keepCurrent
    }
}
