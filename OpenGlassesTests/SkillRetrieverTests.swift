import XCTest
@testable import OpenGlasses

/// Headless tests for the skill-retrieval pure core: exact-trigger keep + top-K-by-similarity
/// selection, with the similarity function injected so no embedding model is needed. No store, no UI.
final class SkillRetrieverTests: XCTestCase {

    // MARK: - Helpers

    private func candidate(_ id: String, trigger: String = "", text: String = "") -> SkillCandidate {
        SkillCandidate(id: id, trigger: trigger, matchText: text.isEmpty ? id : text, source: .voice)
    }

    /// A similarity function backed by an explicit id→score table (default 0).
    private func sim(_ scores: [String: Float]) -> (SkillCandidate) -> Float {
        { scores[$0.id] ?? 0 }
    }

    private func ids(_ candidates: [SkillCandidate]) -> [String] { candidates.map(\.id) }

    // MARK: - No-op below the floor

    func testBelowMinCountReturnsAllUnchanged() {
        let cands = [candidate("a"), candidate("b"), candidate("c")]
        let out = SkillRetriever.select(turn: "anything", candidates: cands,
                                        similarity: sim([:]), topK: 1, minCount: 5)
        XCTAssertEqual(ids(out), ["a", "b", "c"])   // count (3) <= minCount (5) → dump all
    }

    func testAtMinCountIsStillNoOp() {
        let cands = [candidate("a"), candidate("b")]
        let out = SkillRetriever.select(turn: "x", candidates: cands,
                                        similarity: sim([:]), topK: 1, minCount: 2)
        XCTAssertEqual(ids(out), ["a", "b"])        // count == minCount → not "past the floor"
    }

    func testEmptyTurnReturnsAll() {
        let cands = (0..<5).map { candidate("s\($0)") }
        let out = SkillRetriever.select(turn: "   ", candidates: cands,
                                        similarity: sim([:]), topK: 1, minCount: 1)
        XCTAssertEqual(out.count, 5)                // no turn → can't rank → dump all
    }

    func testEmptyCandidatesReturnsEmpty() {
        let out = SkillRetriever.select(turn: "hi", candidates: [],
                                        similarity: sim([:]), topK: 3, minCount: 0)
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - Exact trigger keep

    func testExactTriggerMatchAlwaysIncludedDespiteZeroSimilarity() {
        let cands = [
            candidate("hit", trigger: "expense this", text: "irrelevant"),
            candidate("a"), candidate("b"), candidate("c"), candidate("d"),
        ]
        // topK=1 and "hit" has zero similarity, but its trigger appears in the turn → kept.
        let out = SkillRetriever.select(turn: "please expense this receipt", candidates: cands,
                                        similarity: sim(["a": 0.9]), topK: 1, minCount: 2)
        XCTAssertTrue(ids(out).contains("hit"))
    }

    func testTriggerMatchKeptEvenBeyondTopKBudget() {
        let cands = [
            candidate("t1", trigger: "log water"),
            candidate("t2", trigger: "log food"),
            candidate("t3", trigger: "log mood"),
            candidate("x1"), candidate("x2"),
        ]
        // All three triggers appear in the turn; topK is only 1 — every trigger match still survives.
        let out = SkillRetriever.select(turn: "log water, log food, and log mood",
                                        candidates: cands, similarity: sim([:]), topK: 1, minCount: 2)
        XCTAssertEqual(Set(ids(out)), ["t1", "t2", "t3"])
    }

    func testCaseInsensitiveTriggerMatch() {
        let cands = [candidate("hit", trigger: "Stand Up Meeting")] + (0..<4).map { candidate("f\($0)") }
        let out = SkillRetriever.select(turn: "start my stand up meeting now", candidates: cands,
                                        similarity: sim([:]), topK: 1, minCount: 2)
        XCTAssertTrue(ids(out).contains("hit"))
    }

    func testBlankTriggerNotForceIncluded() {
        // An empty trigger must not be treated as "matches everything" (an empty string is a
        // substring of any turn). Give the others real similarity so the budget is filled by them —
        // the only way "blank" could appear here is via a (wrong) trigger force-match.
        let cands = [candidate("blank", trigger: "")] + (1...4).map { candidate("f\($0)") }
        let out = SkillRetriever.select(
            turn: "hello world", candidates: cands,
            similarity: sim(["f1": 0.9, "f2": 0.8, "f3": 0.7, "f4": 0.6]),
            topK: 2, minCount: 2)
        XCTAssertEqual(Set(ids(out)), ["f1", "f2"])     // budget filled by similarity; blank not force-kept
    }

    // MARK: - Top-K by similarity

    func testFillsRemainingBudgetByHighestSimilarity() {
        let cands = [candidate("a"), candidate("b"), candidate("c"), candidate("d"), candidate("e")]
        let out = SkillRetriever.select(
            turn: "rank me", candidates: cands,
            similarity: sim(["a": 0.1, "b": 0.9, "c": 0.5, "d": 0.8, "e": 0.2]),
            topK: 2, minCount: 1)
        XCTAssertEqual(Set(ids(out)), ["b", "d"])   // the two highest scores
    }

    func testTopKBudgetRespectedWithoutTriggerMatches() {
        let cands = (0..<6).map { candidate("s\($0)") }
        let scores = Dictionary(uniqueKeysWithValues: (0..<6).map { ("s\($0)", Float($0)) })
        let out = SkillRetriever.select(turn: "go", candidates: cands,
                                        similarity: sim(scores), topK: 3, minCount: 1)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(Set(ids(out)), ["s5", "s4", "s3"])   // top 3 by score
    }

    func testTriggerMatchesCountAgainstBudget() {
        let cands = [
            candidate("trig", trigger: "report"),
            candidate("a"), candidate("b"), candidate("c"),
        ]
        // topK=2: the trigger match takes one slot, leaving one for the best similarity ("b").
        let out = SkillRetriever.select(turn: "make a report", candidates: cands,
                                        similarity: sim(["a": 0.2, "b": 0.9, "c": 0.1]),
                                        topK: 2, minCount: 1)
        XCTAssertEqual(Set(ids(out)), ["trig", "b"])
    }

    // MARK: - Stable ordering

    func testOutputPreservesOriginalOrder() {
        let cands = [candidate("a"), candidate("b"), candidate("c"), candidate("d")]
        let out = SkillRetriever.select(turn: "go", candidates: cands,
                                        similarity: sim(["d": 0.9, "a": 0.8]), topK: 2, minCount: 1)
        XCTAssertEqual(ids(out), ["a", "d"])        // selected {a,d} returned in input order, not score order
    }

    func testSimilarityTiesBreakByOriginalOrder() {
        let cands = (0..<5).map { candidate("s\($0)") }
        // All equal similarity; topK=2 → the first two in original order win the tie-break.
        let out = SkillRetriever.select(turn: "go", candidates: cands,
                                        similarity: { _ in 0.5 }, topK: 2, minCount: 1)
        XCTAssertEqual(ids(out), ["s0", "s1"])
    }
}
