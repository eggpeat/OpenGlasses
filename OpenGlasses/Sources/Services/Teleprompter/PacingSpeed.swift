import Foundation

/// Live-adjustable prompting speed.
/// - `wpm` drives the fixed auto-scroll timer.
/// - `leadLines` is how far ahead of the spoken word the audio-paced window sits.
/// - `responsiveness` (0…1) biases how eagerly the aligner accepts a jump.
/// All values are clamped to sane bounds on every mutation.
struct PacingSpeed: Equatable {
    private(set) var wpm: Int
    private(set) var leadLines: Int
    private(set) var responsiveness: Double

    static let wpmRange = 60...240
    static let leadRange = 0...4
    static let responsivenessRange = 0.0...1.0
    static let `default` = PacingSpeed()

    init(wpm: Int = 130, leadLines: Int = 1, responsiveness: Double = 0.5) {
        self.wpm = Self.clamp(wpm, Self.wpmRange)
        self.leadLines = Self.clamp(leadLines, Self.leadRange)
        self.responsiveness = Self.clamp(responsiveness, Self.responsivenessRange)
    }

    mutating func setWPM(_ value: Int) { wpm = Self.clamp(value, Self.wpmRange) }
    mutating func nudgeWPM(_ delta: Int) { setWPM(wpm + delta) }
    mutating func setLead(_ lines: Int) { leadLines = Self.clamp(lines, Self.leadRange) }
    mutating func setResponsiveness(_ value: Double) {
        responsiveness = Self.clamp(value, Self.responsivenessRange)
    }

    /// Seconds per word at the current WPM — drives the auto-scroll timer.
    var secondsPerWord: Double { 60.0 / Double(wpm) }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
