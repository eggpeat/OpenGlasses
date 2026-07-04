import Foundation

/// The execution skeleton of one LLM turn (Plan BG P2): send → post-process → cancellation check →
/// accept → speak, with a `finish` stage that ALWAYS runs — success, error, or cancellation.
///
/// `handleTranscription`'s photo and normal turns both run this skeleton inside the tracked
/// `currentLLMTask`; only the stage bodies differ, so they are injected as `@MainActor` closures
/// that capture the live `AppState` (same pattern as `VoiceCommandHandler` — no wide protocol seam).
/// That makes the spine's ordering guarantees unit-testable with recorder closures:
///
/// - A response is only accepted/spoken if the turn wasn't cancelled while the LLM worked
///   (barge-in / stop must never speak a stale reply).
/// - An error mid-flow still reaches `finish`, so the app resumes listening or returns to the
///   wake word instead of sticking in the processing state (the July 2026 audit's
///   stuck-listening scenario).
enum ConversationTurnRunner {

    /// The seams of one turn. All closures are main-actor isolated because they mutate
    /// `AppState`'s published properties and drive UI-adjacent services.
    struct Deps {
        /// Produce the raw LLM response (photo capture + vision call, local agent, or cloud call).
        let send: @MainActor () async throws -> String
        /// Transform the raw response before it is accepted (memory-command parsing; identity
        /// when user memory is disabled).
        let postProcess: @MainActor (String) async -> String
        /// Accept the final response: publish it, persist it, log it.
        let accept: @MainActor (String) async -> Void
        /// Speak the response (wrapped in the stop-listener on the live host).
        let speak: @MainActor (String) async -> Void
        /// The turn was cancelled (barge-in / stop / cancel) — nothing was accepted or spoken.
        let onCancelled: @MainActor () -> Void
        /// `send` failed with a non-cancellation error: publish/speak the failure.
        let onError: @MainActor (Error) async -> Void
        /// Always runs last, on every path: restore any temporary model switch, clear the
        /// processing state, resume listening or return to the wake word.
        let finish: @MainActor () async -> Void
    }

    @MainActor
    static func run(_ deps: Deps) async {
        do {
            let raw = try await deps.send()
            let response = await deps.postProcess(raw)
            // If the user barged in / stopped while the LLM was working, don't accept or speak
            // the now-stale reply.
            try Task.checkCancellation()
            await deps.accept(response)
            await deps.speak(response)
        } catch is CancellationError {
            deps.onCancelled()
        } catch {
            await deps.onError(error)
        }
        await deps.finish()
    }
}
