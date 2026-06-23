import Foundation

/// A segment of a chat message: inline-markdown prose, or a fenced code block.
/// Pure value model — produced by `MarkdownBlockParser`, rendered by `MessageContentView`.
enum MarkdownBlock: Equatable {
    case prose(String)
    case code(language: String?, body: String)
}

/// Splits assistant/user message text into ordered prose and fenced-code segments by scanning
/// for triple-backtick fences. No I/O, no rendering — fully unit-testable.
///
/// Rules:
/// - A fence is a line whose trimmed content starts with ```` ``` ```` (optionally followed by a
///   language tag, e.g. ```` ```swift ````).
/// - Everything between an opening fence and the next closing fence is the code body, captured
///   verbatim (indentation and blank lines preserved).
/// - An unterminated opening fence captures the remainder of the text as code.
/// - Prose runs between/around code blocks; whitespace-only prose runs are dropped.
enum MarkdownBlockParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var proseLines: [String] = []
        var codeLines: [String] = []
        var inCode = false
        var codeLang: String?

        func flushProse() {
            let joined = proseLines.joined(separator: "\n")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { blocks.append(.prose(trimmed)) }
            proseLines.removeAll()
        }
        func flushCode() {
            blocks.append(.code(language: codeLang, body: codeLines.joined(separator: "\n")))
            codeLines.removeAll()
            codeLang = nil
        }

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushProse()
                    let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                    inCode = true
                }
            } else if inCode {
                codeLines.append(line)
            } else {
                proseLines.append(line)
            }
        }

        if inCode { flushCode() } else { flushProse() }
        return blocks
    }
}
