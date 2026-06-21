import Foundation

/// One screen's worth of the script, computed purely from the cursor + display geometry.
struct TeleprompterWindow: Equatable {
    /// Wrapped display lines, top-to-bottom.
    let lines: [String]
    /// Which entry in `lines` is the line currently being spoken (0 = top).
    let activeLineIndex: Int
    /// 0…1 progress through the whole script.
    let progress: Double
}

/// Turns a cursor position into the visible window of script lines for the HUD. Pure — given a
/// script + cursor + geometry it always returns the same window, so it's fully testable
/// without a display. Honors the existing "paginate, don't scroll" HUD model.
enum TeleprompterPaginator {
    struct Geometry {
        /// Display lines that fit in the HUD window.
        var maxLines: Int
        /// Characters per display line before wrapping.
        var maxChars: Int

        static let raybanDisplay = Geometry(maxLines: 4, maxChars: 32)
        static let evenG2 = Geometry(maxLines: 3, maxChars: 40)
    }

    static func window(_ script: TeleprompterScript, cursor: Int,
                       geometry: Geometry = .raybanDisplay) -> TeleprompterWindow {
        let n = script.tokens.count
        let progress = n == 0 ? 1.0 : Double(min(max(cursor, 0), n)) / Double(n)
        guard n > 0 else { return TeleprompterWindow(lines: [], activeLineIndex: 0, progress: 1.0) }

        let tokenIndex = min(max(cursor, 0), n - 1)
        let activeLine = script.tokens[tokenIndex].line

        // Show from the active source line forward, wrapping long lines, skipping blanks.
        var display: [String] = []
        var lineIndex = activeLine
        while lineIndex < script.lines.count && display.count < geometry.maxLines {
            let raw = script.lines[lineIndex].trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty {
                for wrapped in wrap(raw, maxChars: geometry.maxChars) where display.count < geometry.maxLines {
                    display.append(wrapped)
                }
            }
            lineIndex += 1
        }

        return TeleprompterWindow(lines: display, activeLineIndex: 0, progress: progress)
    }

    /// Word-wrap a line to `maxChars`, hard-splitting any single word longer than the limit.
    static func wrap(_ line: String, maxChars: Int) -> [String] {
        guard maxChars > 0, line.count > maxChars else { return [line] }
        var out: [String] = []
        var current = ""
        for word in line.split(separator: " ") {
            let w = String(word)
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= maxChars {
                current += " " + w
            } else {
                out.append(current)
                current = w
            }
            while current.count > maxChars {
                out.append(String(current.prefix(maxChars)))
                current = String(current.dropFirst(maxChars))
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
