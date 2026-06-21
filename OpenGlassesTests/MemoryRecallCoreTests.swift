import XCTest
@testable import OpenGlasses

/// Headless tests for the Memory/Recall pure core (Phase 1): FTS query builder, the FTS5
/// conversation index, and the self-improving analyzers + insights aggregator. No model,
/// no UI, no hardware.
final class MemoryRecallCoreTests: XCTestCase {

    // MARK: - FTSQueryBuilder

    func testBuildExtractsContentWordsAndDropsStopwords() {
        let q = FTSQueryBuilder.build("what did we decide about the museum app", now: Date())
        XCTAssertNil(q.since)
        // Only content words survive, each quoted, OR-joined.
        XCTAssertEqual(q.match, "\"decide\" OR \"museum\" OR \"app\"")
    }

    func testBuildAllStopwordsYieldsNilMatch() {
        let q = FTSQueryBuilder.build("what did we talk about", now: Date())
        XCTAssertNil(q.match)
        XCTAssertNil(q.since)
        XCTAssertTrue(q.isEmpty)
    }

    func testBuildDetectsYesterdayWindowAndStripsDateWords() {
        let cal = Calendar.current
        let now = Date()
        let q = FTSQueryBuilder.build("what did we discuss yesterday", now: now, calendar: cal)
        let startToday = cal.startOfDay(for: now)
        XCTAssertEqual(q.since, cal.date(byAdding: .day, value: -1, to: startToday))
        XCTAssertEqual(q.until, startToday)
        XCTAssertNil(q.match)   // "discuss" is a stopword; "yesterday" is a date word
    }

    func testBuildDetectsLastWeekWithContent() {
        let q = FTSQueryBuilder.build("the budget last week", now: Date())
        XCTAssertNotNil(q.since)
        XCTAssertNotNil(q.until)
        XCTAssertEqual(q.match, "\"budget\"")   // "last"/"week" consumed by date detection
    }

    // MARK: - ConversationIndex

    private func makeIndex() -> ConversationIndex {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("idx-\(UUID().uuidString).sqlite")
        return ConversationIndex(dbURL: url)
    }

    private func turn(_ id: String, _ text: String, role: String = "user",
                      thread: String = "t1", at date: Date = Date()) -> IndexedTurn {
        IndexedTurn(id: id, threadID: thread, role: role, text: text, timestamp: date)
    }

    func testIndexAndFullTextSearch() {
        let idx = makeIndex()
        idx.index(turn("a", "We decided to ship the museum docent feature next sprint"))
        idx.index(turn("b", "The weather tomorrow looks rainy"))
        XCTAssertEqual(idx.count(), 2)

        let hits = idx.search(phrase: "museum feature")
        XCTAssertEqual(hits.first?.id, "a")
        XCTAssertFalse(hits.contains { $0.id == "b" })
        XCTAssertFalse(hits.first?.snippet.isEmpty ?? true)
    }

    func testReindexIsIdempotent() {
        let idx = makeIndex()
        idx.index(turn("a", "original text about coffee"))
        idx.index(turn("a", "updated text about espresso"))   // same id
        XCTAssertEqual(idx.count(), 1)
        XCTAssertTrue(idx.search(phrase: "espresso").contains { $0.id == "a" })
        XCTAssertTrue(idx.search(phrase: "coffee").isEmpty)
    }

    func testDateWindowFiltersResults() {
        let idx = makeIndex()
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now)!
        idx.index(turn("today", "standup notes", at: now))
        idx.index(turn("old", "older standup notes", at: twoDaysAgo))

        // Date-only query (no MATCH) for "today" → only today's turn.
        let q = ParsedQuery(match: nil, since: today, until: cal.date(byAdding: .day, value: 1, to: today))
        let hits = idx.search(q)
        XCTAssertEqual(hits.map(\.id), ["today"])
    }

    func testEmptyQueryReturnsRecentFirst() {
        let idx = makeIndex()
        let now = Date()
        idx.index(turn("older", "first", at: now.addingTimeInterval(-100)))
        idx.index(turn("newer", "second", at: now))
        let hits = idx.search(ParsedQuery(match: nil, since: nil, until: nil), limit: 10)
        XCTAssertEqual(hits.first?.id, "newer")   // ORDER BY ts DESC
    }

    // MARK: - MemoryNudgeAnalyzer

    func testNudgeExplicitCueExtractsPayload() {
        let n = MemoryNudgeAnalyzer.nudge(for: CompletedTurn(userText: "Remember that the wifi password is hunter2"))
        XCTAssertEqual(n?.kind, .fact)
        XCTAssertEqual(n?.payload, "the wifi password is hunter2")
    }

    func testNudgeDurableStatement() {
        XCTAssertEqual(MemoryNudgeAnalyzer.nudge(for: CompletedTurn(userText: "My daughter's name is Mia"))?.payload,
                       "My daughter's name is Mia")
    }

    func testNudgeSkipsQuestionsAndSmalltalk() {
        XCTAssertNil(MemoryNudgeAnalyzer.nudge(for: CompletedTurn(userText: "What's the weather today?")))
        XCTAssertNil(MemoryNudgeAnalyzer.nudge(for: CompletedTurn(userText: "thanks!")))
        XCTAssertNil(MemoryNudgeAnalyzer.nudge(for: CompletedTurn(userText: "how do I get home")))
    }

    // MARK: - SkillPatternDetector

    func testSkillSuggestedAfterThreshold() {
        let d = SkillPatternDetector(threshold: 3)
        let tools = ["get_weather", "get_news"]
        XCTAssertNil(d.record(toolNames: tools, triggerHint: "morning brief"))
        XCTAssertNil(d.record(toolNames: tools, triggerHint: "morning brief"))
        let s = d.record(toolNames: tools, triggerHint: "morning brief")
        XCTAssertEqual(s?.toolSignature, tools)
        XCTAssertEqual(s?.count, 3)
        // Doesn't re-suggest the same sequence.
        XCTAssertNil(d.record(toolNames: tools, triggerHint: "morning brief"))
    }

    func testSkillIgnoresSingleToolTurns() {
        let d = SkillPatternDetector(threshold: 2)
        XCTAssertNil(d.record(toolNames: ["set_timer"], triggerHint: "timer"))
        XCTAssertNil(d.record(toolNames: ["set_timer"], triggerHint: "timer"))
    }

    // MARK: - InsightsAggregator

    func testInsightsCountsToolsAndTopics() {
        let now = Date()
        let since = now.addingTimeInterval(-3600)
        let events = [
            InsightEvent(timestamp: now.addingTimeInterval(-100), role: "user", toolNames: [], text: "remind me about the museum proposal"),
            InsightEvent(timestamp: now.addingTimeInterval(-90), role: "assistant", toolNames: ["reminder"], text: ""),
            InsightEvent(timestamp: now.addingTimeInterval(-50), role: "user", toolNames: [], text: "what's on my museum calendar"),
            InsightEvent(timestamp: now.addingTimeInterval(-40), role: "assistant", toolNames: ["calendar", "reminder"], text: ""),
        ]
        let r = InsightsAggregator.aggregate(events, since: since, now: now)
        XCTAssertEqual(r.totalTurns, 4)
        XCTAssertEqual(r.userTurns, 2)
        XCTAssertEqual(r.topTools.first?.name, "reminder")   // appears twice
        XCTAssertEqual(r.topTools.first?.count, 2)
        XCTAssertEqual(r.topTopics.first?.name, "museum")    // in both user turns
        XCTAssertTrue(r.summary.contains("4 turns"))
    }

    func testInsightsWindowExcludesOldAndEmpty() {
        let now = Date()
        let since = now.addingTimeInterval(-3600)
        let old = InsightEvent(timestamp: now.addingTimeInterval(-99999), role: "user", toolNames: ["x"], text: "old")
        let r = InsightsAggregator.aggregate([old], since: since, now: now)
        XCTAssertEqual(r.totalTurns, 0)
        XCTAssertTrue(r.summary.contains("No activity"))
    }
}
