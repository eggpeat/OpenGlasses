import XCTest
@testable import OpenGlasses

final class UsageTrackerTests: XCTestCase {

    // MARK: - ModelPricing

    func testKnownModelPricesCorrectly() throws {
        // Sonnet 4 = $3 / 1M in, $15 / 1M out. 1M in + 1M out = $18.
        let cost = ModelPricing.estimate(model: "claude-sonnet-4-20250514", tokensIn: 1_000_000, tokensOut: 1_000_000)
        XCTAssertEqual(try XCTUnwrap(cost), 18.0, accuracy: 1e-9)
    }

    func testDatedModelIdResolvesToFamilyByLongestPrefix() {
        // gpt-4o-mini must beat gpt-4o despite both being prefixes.
        let mini = ModelPricing.rate(for: "gpt-4o-mini-2024-07-18")
        XCTAssertEqual(mini, ModelPricing.Rate(0.15, 0.60))
        let full = ModelPricing.rate(for: "gpt-4o-2024-11-20")
        XCTAssertEqual(full, ModelPricing.Rate(2.50, 10))
        // Current-gen Opus has its own (longer) prefix entry at current pricing…
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-4-8"), ModelPricing.Rate(5, 25))
        // …while older dated Opus ids still fall back to the opus family rate.
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-4-1-20250805"), ModelPricing.Rate(15, 75))
    }

    func testUnknownModelIsNil() {
        XCTAssertNil(ModelPricing.estimate(model: "totally-made-up-model", tokensIn: 1000, tokensOut: 1000))
        XCTAssertNil(ModelPricing.rate(for: "mystery"))
    }

    func testZeroTokensAtKnownRateIsZeroNotNil() throws {
        let cost = ModelPricing.estimate(model: "gpt-4o", tokensIn: 0, tokensOut: 0)
        XCTAssertEqual(try XCTUnwrap(cost), 0.0, accuracy: 1e-9)
    }

    func testOverrideTakesPrecedence() {
        ModelPricing.overrides = ["gpt-4o": ModelPricing.Rate(99, 99)]
        defer { ModelPricing.overrides = [:] }
        XCTAssertEqual(ModelPricing.rate(for: "gpt-4o"), ModelPricing.Rate(99, 99))
    }

    // MARK: - UsageRollup

    private func rec(_ model: String, _ tIn: Int, _ tOut: Int, _ cost: Double?, at: Date) -> UsageRecord {
        UsageRecord(sessionId: "s", provider: "p", model: model, tokensIn: tIn, tokensOut: tOut, costUSD: cost, at: at)
    }

    func testRollupEmpty() {
        let r = UsageRollup.rollup([], since: Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertTrue(r.perModel.isEmpty)
        XCTAssertEqual(r.totalTokensIn, 0)
        XCTAssertNil(r.totalUSD)
    }

    func testRollupAggregatesPerModelAndTotal() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let records = [
            rec("a", 100, 50, 0.10, at: now),
            rec("a", 200, 100, 0.20, at: now),
            rec("b", 10, 5, 0.01, at: now)
        ]
        let r = UsageRollup.rollup(records, since: now.addingTimeInterval(-1))
        XCTAssertEqual(r.perModel.count, 2)
        // "a" has more tokens → sorted first.
        XCTAssertEqual(r.perModel.first?.model, "a")
        XCTAssertEqual(r.perModel.first?.tokensIn, 300)
        XCTAssertEqual(r.perModel.first?.tokensOut, 150)
        XCTAssertEqual(try XCTUnwrap(r.perModel.first?.costUSD ?? nil), 0.30, accuracy: 1e-9)
        XCTAssertEqual(r.totalTokensIn, 310)
        XCTAssertEqual(r.totalTokensOut, 155)
        XCTAssertEqual(try XCTUnwrap(r.totalUSD), 0.31, accuracy: 1e-9)
    }

    func testRollupExcludesOutOfWindow() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let records = [
            rec("a", 100, 50, 0.10, at: now),                    // in window
            rec("a", 999, 999, 9.99, at: now.addingTimeInterval(-100)) // before window
        ]
        let r = UsageRollup.rollup(records, since: now.addingTimeInterval(-10))
        XCTAssertEqual(r.totalTokensIn, 100)
        XCTAssertEqual(try XCTUnwrap(r.totalUSD), 0.10, accuracy: 1e-9)
    }

    func testRollupUnpricedModelOmitsItsDollarButKeepsTokens() throws {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let records = [
            rec("priced", 100, 100, 0.50, at: now),
            rec("unpriced", 200, 200, nil, at: now)
        ]
        let r = UsageRollup.rollup(records, since: now.addingTimeInterval(-1))
        let unpriced = try XCTUnwrap(r.perModel.first { $0.model == "unpriced" })
        XCTAssertNil(unpriced.costUSD)
        XCTAssertEqual(unpriced.tokensIn, 200)
        // Total dollars = only the priced record; tokens include both.
        XCTAssertEqual(try XCTUnwrap(r.totalUSD), 0.50, accuracy: 1e-9)
        XCTAssertEqual(r.totalTokensIn, 300)
    }

    func testRollupAllUnpricedTotalIsNil() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let r = UsageRollup.rollup([rec("x", 10, 10, nil, at: now)], since: now.addingTimeInterval(-1))
        XCTAssertNil(r.totalUSD)
        XCTAssertEqual(r.totalTokensIn, 10)
    }

    // MARK: - parseTokens

    func testParseTokensPerProvider() {
        let anthropic: [String: Any] = ["usage": ["input_tokens": 12, "output_tokens": 34]]
        XCTAssertEqual(UsageTracker.parseTokens(provider: .anthropic, json: anthropic)?.tokensIn, 12)
        XCTAssertEqual(UsageTracker.parseTokens(provider: .anthropic, json: anthropic)?.tokensOut, 34)

        let openai: [String: Any] = ["usage": ["prompt_tokens": 5, "completion_tokens": 7]]
        XCTAssertEqual(UsageTracker.parseTokens(provider: .openai, json: openai)?.tokensIn, 5)
        XCTAssertEqual(UsageTracker.parseTokens(provider: .openai, json: openai)?.tokensOut, 7)

        let gemini: [String: Any] = ["usageMetadata": ["promptTokenCount": 8, "candidatesTokenCount": 9]]
        XCTAssertEqual(UsageTracker.parseTokens(provider: .gemini, json: gemini)?.tokensIn, 8)
        XCTAssertEqual(UsageTracker.parseTokens(provider: .gemini, json: gemini)?.tokensOut, 9)

        // No usage block → nil.
        XCTAssertNil(UsageTracker.parseTokens(provider: .anthropic, json: ["content": []]))
    }

    // MARK: - UsageStore (SQLite)

    @MainActor
    func testStoreInsertFetchAndSurvivesReopen() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: path) }

        let now = Date(timeIntervalSinceReferenceDate: 50_000)
        do {
            let store = UsageStore(path: path)
            store.deleteAll()
            store.insert(UsageRecord(sessionId: "s1", provider: "anthropic", model: "claude-sonnet-4",
                                     tokensIn: 100, tokensOut: 50, costUSD: 0.001, at: now))
            store.insert(UsageRecord(sessionId: "s1", provider: "openai", model: "weird-model",
                                     tokensIn: 10, tokensOut: 5, costUSD: nil, at: now))
            XCTAssertEqual(store.records(since: now.addingTimeInterval(-1)).count, 2)
            // Out-of-window excluded.
            XCTAssertEqual(store.records(since: now.addingTimeInterval(1)).count, 0)
        }

        // Reopen the same file: rows survive, and the NULL cost round-trips as nil.
        let reopened = UsageStore(path: path)
        let rows = reopened.records(since: now.addingTimeInterval(-1))
        XCTAssertEqual(rows.count, 2)
        let unpriced = try XCTUnwrap(rows.first { $0.model == "weird-model" })
        XCTAssertNil(unpriced.costUSD)
        let priced = try XCTUnwrap(rows.first { $0.model == "claude-sonnet-4" })
        XCTAssertEqual(try XCTUnwrap(priced.costUSD), 0.001, accuracy: 1e-9)
    }

    @MainActor
    func testStoreRollupConvenience() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        let now = Date(timeIntervalSinceReferenceDate: 60_000)
        let store = UsageStore(path: path)
        store.insert(UsageRecord(sessionId: "s", provider: "p", model: "m", tokensIn: 100, tokensOut: 100, costUSD: 0.20, at: now))
        let r = store.rollup(days: 7, now: now)
        XCTAssertEqual(r.totalTokensIn, 100)
        XCTAssertEqual(try XCTUnwrap(r.totalUSD), 0.20, accuracy: 1e-9)
    }
}
