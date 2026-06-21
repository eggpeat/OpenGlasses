import Foundation

/// Pure speech → script-position tracker: the heart of audio pacing.
///
/// Given the script's normalized tokens, the current cursor (index of the next unspoken
/// word), and a rolling buffer of recognized (normalized) tokens, it returns the updated
/// cursor. It **anchors on the most recent heard word** and corroborates with the words just
/// before it, so leading mis-recognition or filler doesn't throw it off. It holds position on
/// silence / off-script speech, and resists spurious backward jumps.
///
/// Entirely deterministic and side-effect-free, so the pacing logic is fully unit-tested
/// before any live recognition or hardware is involved.
enum ScriptAligner {
    struct Config {
        /// How many words ahead of the cursor we'll look (tolerates skipped lines).
        var lookAhead = 12
        /// How far behind the cursor we'll look (small corrections / re-reads).
        var lookBack = 6
        /// Max backward context words used to corroborate an anchor match.
        var maxSupport = 4
        /// A lone last-word match only counts if the script position is within this of the cursor.
        var nearForward = 2
        /// Forward jumps beyond `nearForward` need at least this much corroborating support.
        var minSupportForJump = 2
        /// Moving the cursor backward at all needs strong support (deliberate re-read).
        var minSupportForBackward = 3
        /// Levenshtein similarity (0…1) at/above which two words are considered the same.
        var fuzzyThreshold = 0.8

        static let `default` = Config()
    }

    /// `script` and `heard` are already-normalized token arrays (see `TeleprompterText`).
    /// Returns the new cursor (0…script.count).
    static func advance(script: [String], cursor: Int, heard: [String],
                        config: Config = .default) -> Int {
        let n = script.count
        let clampedCursor = min(max(cursor, 0), n)
        guard n > 0, let lastWord = heard.last(where: { !$0.isEmpty }) else { return clampedCursor }

        let lo = max(0, clampedCursor - config.lookBack)
        let hi = min(n - 1, clampedCursor + config.lookAhead)
        guard lo <= hi else { return clampedCursor }

        // Find the script position best explaining the most recent heard word.
        var best: (support: Int, pos: Int)?
        for p in lo...hi where fuzzyEqual(script[p], lastWord, config.fuzzyThreshold) {
            var support = 1
            var heardIdx = heard.count - 2
            var scriptIdx = p - 1
            while support < config.maxSupport, heardIdx >= 0, scriptIdx >= 0,
                  fuzzyEqual(script[scriptIdx], heard[heardIdx], config.fuzzyThreshold) {
                support += 1
                heardIdx -= 1
                scriptIdx -= 1
            }
            if best == nil || support > best!.support ||
               (support == best!.support && abs(p - clampedCursor) < abs(best!.pos - clampedCursor)) {
                best = (support, p)
            }
        }
        guard let match = best else { return clampedCursor }

        let proposed = match.pos + 1
        let delta = match.pos - clampedCursor
        // Gate weak / loose matches to avoid jitter and false jumps.
        if match.support == 1 && !(delta >= 0 && delta <= config.nearForward) { return clampedCursor }
        if delta > config.nearForward && match.support < config.minSupportForJump { return clampedCursor }
        if proposed < clampedCursor && match.support < config.minSupportForBackward { return clampedCursor }
        return min(max(proposed, 0), n)
    }

    // MARK: - Fuzzy word match

    static func fuzzyEqual(_ a: String, _ b: String, _ threshold: Double) -> Bool {
        if a == b { return true }
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return true }
        // Short words must match exactly — a 1-edit ratio is meaningless at length 1–2.
        if maxLen <= 2 { return false }
        let distance = levenshtein(Array(a), Array(b))
        return 1.0 - Double(distance) / Double(maxLen) >= threshold
    }

    static func levenshtein(_ s: [Character], _ t: [Character]) -> Int {
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var cur = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            cur[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }
}
