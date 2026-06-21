import AppIntents

/// Conversational Siri intent: speak a question and route it through the full
/// LLM/persona pipeline, then have Siri read the answer back.
///
/// This is the "Hey Siri" entry point that mirrors how third-party projects wake
/// the glasses workflow from Siri (e.g. a Siri Shortcut wrapping an App Intent).
/// Unlike `AskOpenGlassesIntent` — which only starts the microphone — this intent
/// answers in-line and has Siri speak the result.
///
/// **Two-step conversation.** A free-form `String` can't be carried inside an
/// `AppShortcut` phrase (the AppIntents metadata processor only allows `AppEntity`
/// / `AppEnum`-typed parameters there), so the flow is deliberately two-step:
///
///   1. **"Hey Siri, ask OpenGlasses a question"** → Siri resolves the missing
///      `question` parameter via `requestValueDialog` ("What would you like to
///      ask?") and awaits the spoken reply.
///   2. The reply is routed through `sendTextMessage` and Siri speaks the answer.
///
/// Because the intent runs in the background by default (`openAppWhenRun == false`
/// unless the user flips `Config.siriAskOpensApp`), Siri can invoke `perform()`
/// before the app scene is fully resident — increasingly so under the more
/// background-driven, conversational Siri in iOS 27. So step 1 first *awaits a
/// connection signal*: it waits briefly for `AppStateProvider.shared` to come up
/// rather than failing the instant it's nil. The answer is returned as a spoken
/// `dialog`, so Siri — not the in-app TTS — reads it aloud (`speakResponse: false`).
struct AskQuestionIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask OpenGlasses a Question"
    static var description = IntentDescription(
        "Ask OpenGlasses anything by voice and hear the answer, without the wake word"
    )

    // By default, run in the background so Siri can speak the answer without forcing
    // the app to the foreground (OpenGlasses normally stays running for wake words,
    // so `AppStateProvider.shared` is populated). Users who'd rather guarantee it
    // launches can flip "Open app for Siri questions" in Settings.
    static var openAppWhenRun: Bool { Config.siriAskOpensApp }
    static var isDiscoverable: Bool { true }

    /// How long to wait for the app to signal it's up before giving up (step 1).
    private static let connectionTimeout: Duration = .seconds(4)
    private static let connectionPollInterval: Duration = .milliseconds(100)

    @Parameter(
        title: "Question",
        description: "What you want to ask OpenGlasses",
        requestValueDialog: "What would you like to ask?"
    )
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Step 1 — await the connection signal. The app may not be wired up the
        // instant Siri calls us (background invocation, or a fresh launch when
        // `siriAskOpensApp` is on), so wait briefly instead of failing immediately.
        let appState = try await awaitConnectedAppState()

        // Don't ride on a stale `lastResponse`: if a wake-word/voice turn is already
        // in flight, `sendTextMessage` would no-op and we'd speak the previous answer.
        guard !appState.isProcessing else {
            throw IntentError.busy
        }

        // Step 2 — the question is resolved two-step by Siri (requestValueDialog)
        // before we get here, so `question` is populated; guard the empty edge case.
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntentError.emptyQuestion
        }

        // Route through the same pipeline the wake word uses, but let Siri speak
        // the result instead of the in-app TTS engine.
        await appState.sendTextMessage(trimmed, speakResponse: false)

        let answer = appState.lastResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            throw IntentError.noResponse
        }

        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }

    /// Wait up to `connectionTimeout` for the app to signal it's running and wired
    /// up, polling on the main actor. Returns as soon as `AppStateProvider.shared`
    /// is available; throws `appNotRunning` only if the signal never arrives (the
    /// app was killed and not relaunched). A no-op when the app is already resident.
    @MainActor
    private func awaitConnectedAppState() async throws -> AppState {
        if let appState = AppStateProvider.shared { return appState }

        let deadline = ContinuousClock.now + Self.connectionTimeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: Self.connectionPollInterval)
            if let appState = AppStateProvider.shared { return appState }
        }
        throw IntentError.appNotRunning
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case appNotRunning
        case busy
        case emptyQuestion
        case noResponse

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .appNotRunning:
                return "OpenGlasses is not running. Open the app first."
            case .busy:
                return "OpenGlasses is still working on something. Try again in a moment."
            case .emptyQuestion:
                return "I didn't catch a question."
            case .noResponse:
                return "Sorry, I couldn't get an answer."
            }
        }
    }
}
