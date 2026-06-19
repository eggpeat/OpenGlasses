import Foundation

/// PURE Leitner spaced repetition (docs/plans/study-mode.md). A correct answer promotes a card a box
/// (longer interval); a miss demotes it to box 0 (resurfaces soonest). The clock is injected so it's
/// fully deterministic in tests.
struct SpacedRepetition {
    /// Seconds until next review per box; index 0 = box 0 (due immediately).
    let intervals: [TimeInterval]

    init(intervals: [TimeInterval] = [0, 86_400, 3 * 86_400, 7 * 86_400, 14 * 86_400, 30 * 86_400]) {
        self.intervals = intervals.isEmpty ? [0] : intervals
    }

    var maxBox: Int { intervals.count - 1 }

    /// A fresh record for a brand-new card — box 0, due now.
    func newRecord(cardID: String, now: TimeInterval) -> ReviewRecord {
        ReviewRecord(cardID: cardID, box: 0, dueAt: now, lastReviewed: now)
    }

    /// Update a record after a review. Correct → promote a box; incorrect → reset to box 0.
    func update(_ record: ReviewRecord, correct: Bool, now: TimeInterval) -> ReviewRecord {
        let box = correct ? min(record.box + 1, maxBox) : 0
        return ReviewRecord(cardID: record.cardID, box: box, dueAt: now + intervals[box], lastReviewed: now)
    }

    /// Order records by due-ness (most overdue first). Stable for equal due times (sort is stable).
    func dueOrder(_ records: [ReviewRecord], now: TimeInterval) -> [ReviewRecord] {
        records.enumerated()
            .sorted { a, b in a.element.dueAt != b.element.dueAt ? a.element.dueAt < b.element.dueAt : a.offset < b.offset }
            .map(\.element)
    }

    /// Records that are due now (dueAt ≤ now), in due order.
    func due(_ records: [ReviewRecord], now: TimeInterval) -> [ReviewRecord] {
        dueOrder(records.filter { $0.dueAt <= now }, now: now)
    }
}
