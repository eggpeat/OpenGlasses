import Foundation

/// Detects when a user message is **correcting** the assistant's previous answer — a
/// skill-gap signal that complements the tool-failure signal (Plan AW). Pure +
/// headless-testable.
///
/// Deliberately **high-precision**: it matches only correction-specific phrasings, not
/// bare "no" / "actually" (which appear constantly in normal speech — "no problem",
/// "actually that's perfect"). Missing a few corrections is fine; a false positive
/// would pollute the human-reviewed proposal bank.
enum UserCorrectionDetector {

    struct Correction: Equatable { let matchedPhrase: String }

    /// Correction-specific phrases. A match anywhere in the (lowercased) message counts.
    private static let phrases = [
        "that's wrong", "thats wrong", "that is wrong",
        "that's not right", "thats not right", "that is not right",
        "that's incorrect", "thats incorrect", "that's not correct", "that is incorrect",
        "that's not what i", "thats not what i", "that is not what i",
        "not what i meant", "not what i asked", "not what i said",
        "i meant", "i didn't ask", "i didnt ask", "i didn't say", "i didnt say",
        "you're wrong", "youre wrong", "you got that wrong", "you misunderstood",
        "no, that's", "no that's wrong", "wrong answer",
    ]

    /// The correction match, or `nil` if the message doesn't read as a correction.
    static func detect(_ message: String) -> Correction? {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard m.count >= 3 else { return nil }
        for phrase in phrases where m.contains(phrase) {
            return Correction(matchedPhrase: phrase)
        }
        return nil
    }
}
