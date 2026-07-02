import Foundation

/// Pure recognition of the pre-LLM voice commands the conversation flow handles before falling
/// through to the model (docs/plans/BG-spine-refactor.md, P2 groundwork).
///
/// This lifts the stop / goodbye / photo phrase matching and the persona-wake-prefix stripping out
/// of `AppState.handleTranscription` into a deterministic, headless-testable unit. It holds no state
/// and touches no services — `AppState` keeps owning the side effects; this only decides *what* a
/// transcript is.
struct VoiceCommandParser {

    let stopPhrases: [String]
    let goodbyePhrases: [String]
    let photoPhrases: [String]

    /// The phrase sets currently used by the live flow. Kept here as the single source so the
    /// matching rules and the phrases live together.
    static let `default` = VoiceCommandParser(
        stopPhrases: ["stop", "nevermind", "never mind", "cancel", "shut up", "be quiet", "quiet"],
        goodbyePhrases: ["goodbye", "good bye", "bye", "that's all", "thats all",
                         "thanks claude", "thank you claude", "i'm done", "im done",
                         "end conversation", "go to sleep"],
        photoPhrases: ["take a picture", "take a photo", "take photo", "take picture",
                       "capture photo", "snap a photo", "snap a picture", "take a snap"]
    )

    // MARK: - Command recognition

    /// "stop" and friends — matched as a whole word (equal, or a leading/trailing token) so
    /// "stop the timer" counts but "nonstop music" does not.
    func isStop(_ text: String) -> Bool {
        let lower = normalize(text)
        return stopPhrases.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasSuffix(" " + $0) }
    }

    /// "goodbye" and friends — matched as a substring, since these end a conversation and users
    /// pad them ("okay, thanks Claude, bye").
    func isGoodbye(_ text: String) -> Bool {
        let lower = normalize(text)
        return goodbyePhrases.contains { lower.contains($0) }
    }

    /// "take a picture" and friends — substring match.
    func isPhoto(_ text: String) -> Bool {
        let lower = normalize(text)
        return photoPhrases.contains { lower.contains($0) }
    }

    // MARK: - Persona wake-prefix

    /// A persona and the phrases that activate it (its wake phrases + aliases).
    struct PersonaPhrases {
        let id: String
        let phrases: [String]
    }

    /// Result of finding a persona wake-prefix in a transcript.
    struct PersonaMatch: Equatable {
        /// The matched persona's id.
        let personaId: String
        /// The remaining query with the wake phrase stripped, or the original text if stripping
        /// left nothing usable.
        let query: String
    }

    /// Detect a persona wake phrase anywhere in `text` (prefix or contained) and return the matched
    /// persona plus the query with the phrase removed. Mirrors the Action-Button / push-to-talk
    /// path: "Hey Claude, what's the weather" → (claude, "what's the weather").
    func detectPersona(in text: String, personas: [PersonaPhrases]) -> PersonaMatch? {
        let lower = normalize(text)
        for persona in personas {
            for phrase in persona.phrases {
                guard lower.hasPrefix(phrase) || lower.contains(phrase) else { continue }
                var query = text
                if let range = lower.range(of: phrase) {
                    query = String(text[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                        .trimmingCharacters(in: .whitespaces)
                }
                if query.isEmpty { query = text }
                return PersonaMatch(personaId: persona.id, query: query)
            }
        }
        return nil
    }

    private func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
