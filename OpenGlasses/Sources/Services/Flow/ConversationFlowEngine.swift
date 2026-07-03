import Foundation

/// One pre-LLM voice-command handler in the ordered chain (Plan BG P2).
///
/// A handler inspects the transcript and, if it applies, performs its side effect (drive the
/// teleprompter, a HUD card, the launcher, filter bystander speech, …) and reports that it consumed
/// the turn. Consuming the turn stops the flow before the LLM is ever called. Handlers capture the
/// live `AppState` in their closure, so the engine needs no wide protocol seam over it.
struct VoiceCommandHandler {
    /// Short identifier for logging / tests (e.g. "teleprompter", "intent-ignore").
    let label: String
    /// Inspect `text`; return `true` if this handler consumed the turn (flow stops), else `false`.
    let handle: (_ text: String) async -> Bool
}

/// Runs the ordered pre-LLM voice-command chain: the first handler that consumes the transcript
/// wins, and no later handler runs. If none consume it, the transcript falls through to the LLM.
///
/// This is the deterministic core of the conversation flow's routing decision — pure orchestration
/// over injected handlers, so it is unit-testable with mock handlers even though the real handlers
/// drive device-only services.
struct ConversationFlowEngine {
    let handlers: [VoiceCommandHandler]

    /// Route `text` through the chain. Returns the `label` of the handler that consumed the turn,
    /// or `nil` if none did (the caller then proceeds to the LLM path).
    func route(_ text: String) async -> String? {
        for handler in handlers {
            if await handler.handle(text) {
                return handler.label
            }
        }
        return nil
    }
}
