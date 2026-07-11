import Foundation

/// One LLM API call's token usage + estimated cost (Plan AU). Persisted by
/// `UsageStore`; aggregated by `UsageRollup`. Local-only — never leaves the device.
struct UsageRecord: Equatable {
    let id: String
    let sessionId: String
    let provider: String
    let model: String
    let tokensIn: Int
    let tokensOut: Int
    /// Anthropic prompt-cache counts (separate from `tokensIn`): tokens written to and
    /// read from the cache. 0 on providers/turns without caching. Priced into `costUSD`.
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    /// Estimated USD, or `nil` when the model is unpriced (tokens still recorded).
    let costUSD: Double?
    let at: Date

    init(id: String = UUID().uuidString,
         sessionId: String,
         provider: String,
         model: String,
         tokensIn: Int,
         tokensOut: Int,
         cacheWriteTokens: Int = 0,
         cacheReadTokens: Int = 0,
         costUSD: Double?,
         at: Date) {
        self.id = id
        self.sessionId = sessionId
        self.provider = provider
        self.model = model
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.costUSD = costUSD
        self.at = at
    }
}

/// Pure aggregation of `UsageRecord`s into per-model + total tokens/cost over a
/// window. No I/O. A model with no priced records reports `costUSD == nil` (tokens
/// only); the grand `totalUSD` sums the priced records and is `nil` only when none
/// in the window are priced.
enum UsageRollup {

    struct ModelTotal: Equatable {
        let model: String
        let tokensIn: Int
        let tokensOut: Int
        let costUSD: Double?
    }

    struct Result: Equatable {
        let perModel: [ModelTotal]
        let totalTokensIn: Int
        let totalTokensOut: Int
        let totalUSD: Double?
    }

    /// Roll up records with `at >= since`. `perModel` is sorted by total tokens
    /// (descending), then model id for a stable order.
    static func rollup(_ records: [UsageRecord], since: Date) -> Result {
        let inWindow = records.filter { $0.at >= since }

        var byModel: [String: (tIn: Int, tOut: Int, cost: Double?)] = [:]
        for r in inWindow {
            var acc = byModel[r.model] ?? (0, 0, nil)
            acc.tIn += r.tokensIn
            acc.tOut += r.tokensOut
            if let c = r.costUSD {
                acc.cost = (acc.cost ?? 0) + c
            }
            byModel[r.model] = acc
        }

        let perModel = byModel
            .map { ModelTotal(model: $0.key, tokensIn: $0.value.tIn, tokensOut: $0.value.tOut, costUSD: $0.value.cost) }
            .sorted { lhs, rhs in
                let l = lhs.tokensIn + lhs.tokensOut
                let r = rhs.tokensIn + rhs.tokensOut
                return l != r ? l > r : lhs.model < rhs.model
            }

        let totalIn = inWindow.reduce(0) { $0 + $1.tokensIn }
        let totalOut = inWindow.reduce(0) { $0 + $1.tokensOut }
        let pricedCosts = inWindow.compactMap { $0.costUSD }
        let totalUSD: Double? = pricedCosts.isEmpty ? nil : pricedCosts.reduce(0, +)

        return Result(perModel: perModel,
                      totalTokensIn: totalIn,
                      totalTokensOut: totalOut,
                      totalUSD: totalUSD)
    }
}
