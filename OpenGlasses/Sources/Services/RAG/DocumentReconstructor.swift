import Foundation

/// Rebuilds readable document text from `DocumentChunker`'s overlapping, sentence-aware chunks.
/// `DocumentStore` only keeps chunks (each re-includes trailing sentences from the previous one
/// for retrieval), so naively concatenating them would re-read text at every boundary. This
/// de-overlaps at the word level (the repeated run is a contiguous suffix→prefix match) and can
/// re-flow the result one sentence per line for the teleprompter. Pure → fully unit-tested.
enum DocumentReconstructor {

    /// Join ordered chunks back into continuous text, removing the repeated overlap between
    /// consecutive chunks (largest suffix==prefix word run wins).
    static func deOverlap(_ orderedChunks: [String], maxOverlapWords: Int = 80) -> String {
        var result: [String] = []
        for chunk in orderedChunks {
            let words = chunk.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
            guard !words.isEmpty else { continue }
            if result.isEmpty {
                result = words
                continue
            }
            let maxK = min(maxOverlapWords, words.count, result.count)
            var overlap = 0
            var k = maxK
            while k >= 1 {
                if Array(result.suffix(k)) == Array(words.prefix(k)) { overlap = k; break }
                k -= 1
            }
            result.append(contentsOf: words.dropFirst(overlap))
        }
        return result.joined(separator: " ")
    }

    /// Re-flow continuous text to one sentence per line — gives the teleprompter paginator real
    /// line units to scroll through. Splits after `.`/`!`/`?` followed by whitespace (may
    /// over-split abbreviations, which only yields shorter lines — harmless for reading).
    static func scriptLines(_ text: String) -> String {
        var flowed = text
        for ender in [". ", "! ", "? "] {
            flowed = flowed.replacingOccurrences(of: ender, with: "\(ender.first!)\n")
        }
        return flowed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Convenience: ordered chunks → de-overlapped, sentence-per-line script text.
    static func scriptText(fromOrderedChunks chunks: [String]) -> String {
        scriptLines(deOverlap(chunks))
    }
}
