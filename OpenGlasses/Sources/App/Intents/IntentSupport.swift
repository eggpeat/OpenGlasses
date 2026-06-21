import AppIntents

/// Shared helpers for the Siri App Intents.
enum IntentSupport {
    /// Await the app "connection signal" — poll for `AppStateProvider.shared`.
    ///
    /// Siri can invoke a background intent before the app scene is fully resident
    /// (more so under iOS 27's background-driven conversational Siri), so we wait
    /// briefly rather than failing the instant `.shared` is nil. Returns as soon as
    /// the app is up; throws `appNotRunning` only if the signal never arrives.
    @MainActor
    static func awaitConnectedAppState(
        timeout: Duration = .seconds(4),
        pollInterval: Duration = .milliseconds(100)
    ) async throws -> AppState {
        if let appState = AppStateProvider.shared { return appState }

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
            if let appState = AppStateProvider.shared { return appState }
        }
        throw IntentConnectionError.appNotRunning
    }
}

/// Error thrown when a Siri intent can't reach a running app.
enum IntentConnectionError: Error, CustomLocalizedStringResourceConvertible {
    case appNotRunning

    var localizedStringResource: LocalizedStringResource {
        "OpenGlasses is not running. Open the app first."
    }
}
