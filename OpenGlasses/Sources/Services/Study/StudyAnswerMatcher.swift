import Foundation

/// PURE: map a spoken/typed answer to a quiz option (docs/plans/study-mode.md). Tries, in order:
/// an explicit 1-based number ("option two", "2", "the second"), a letter ("b"), then exact/contains
/// text match. Returns the matched option or nil. Headless + testable; real STT accuracy is device-gated.
enum StudyAnswerMatcher {
    static func match(_ spoken: String, options: [QuizOption]) -> QuizOption? {
        let s = spoken.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !options.isEmpty else { return nil }

        // 1) 1-based number (digits or number/ordinal words).
        if let n = number(in: s), options.indices.contains(n - 1) { return options[n - 1] }

        // 2) single letter a/b/c… (only when the input is essentially just the letter).
        if s.count <= 2, let first = s.unicodeScalars.first, let li = letterIndex(first), options.indices.contains(li) {
            return options[li]
        }

        // 3) exact, then containment, text match.
        if let exact = options.first(where: { $0.text.lowercased() == s }) { return exact }
        return options.first { opt in
            let t = opt.text.lowercased()
            return !t.isEmpty && (s.contains(t) || t.contains(s))
        }
    }

    private static let words: [String: Int] = [
        "one": 1, "first": 1, "two": 2, "second": 2, "three": 3, "third": 3,
        "four": 4, "fourth": 4, "five": 5, "fifth": 5, "six": 6, "sixth": 6
    ]

    /// First 1-based number found as a digit or a number/ordinal word.
    private static func number(in s: String) -> Int? {
        let tokens = s.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for t in tokens {
            if let d = Int(t) { return d }
            if let w = words[t] { return w }
        }
        return nil
    }

    private static func letterIndex(_ scalar: Unicode.Scalar) -> Int? {
        let v = scalar.value
        guard v >= 97, v <= 122 else { return nil }   // a–z
        return Int(v - 97)
    }
}
