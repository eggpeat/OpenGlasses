import Foundation

/// One word of a teleprompter script. `normalized` is the lowercased, punctuation-stripped
/// form used for speech matching; `text` is the original as written (for display); `line`
/// indexes into `TeleprompterScript.lines` so the paginator can show the right line.
struct ScriptToken: Equatable {
    let text: String
    let normalized: String
    let line: Int
}

/// A parsed teleprompter script: the original lines (for display) plus the flat token stream
/// (for matching). Pure value type — no I/O, no display dependency.
struct TeleprompterScript: Equatable {
    let title: String
    let lines: [String]
    let tokens: [ScriptToken]

    var wordCount: Int { tokens.count }

    /// Parse raw text into a script. Newlines define lines (blank lines are preserved so the
    /// paginator can treat them as paragraph breaks); whitespace splits words.
    static func parse(title: String, text: String) -> TeleprompterScript {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalizedText.components(separatedBy: "\n")

        var tokens: [ScriptToken] = []
        for (lineIndex, line) in rawLines.enumerated() {
            for word in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let normalized = TeleprompterText.normalize(String(word))
                guard !normalized.isEmpty else { continue }
                tokens.append(ScriptToken(text: String(word), normalized: normalized, line: lineIndex))
            }
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return TeleprompterScript(title: cleanTitle.isEmpty ? "Script" : cleanTitle,
                                  lines: rawLines,
                                  tokens: tokens)
    }
}

/// Word normalization shared by the script tokenizer and the speech side, so a script word
/// and a recognized word compare on the same footing.
enum TeleprompterText {
    /// Lowercase + keep only alphanumerics (drops punctuation, apostrophes, dashes). Digits
    /// are kept so "$20" → "20".
    static func normalize(_ word: String) -> String {
        let scalars = word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Split + normalize a recognized phrase into matchable tokens (empties dropped).
    static func tokenize(_ phrase: String) -> [String] {
        phrase.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }
}
