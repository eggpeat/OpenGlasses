import Foundation

/// Retrieval-quality measurement for choosing an embedding model from evidence rather than vibes.
///
/// The scoring (`recallAtK`, `meanReciprocalRank`) is pure and model-agnostic — feed it any retriever's
/// ranked output. `selfTest` runs a tiny built-in labelled corpus through a given [[Embedder]], so the
/// same number can be read on the `NLEmbedding` baseline (headless) and on `NLContextualEmbedding`
/// on-device once its asset is present.
enum EmbeddingBenchmark {

    struct LabeledQuery: Equatable { let query: String; let relevantId: String }

    /// Fraction of queries whose relevant id appears in the top-`k` ranked results.
    static func recallAtK(_ k: Int,
                          results: [(query: String, rankedIds: [String])],
                          labels: [String: String]) -> Double {
        guard !results.isEmpty, k > 0 else { return 0 }
        let hits = results.reduce(0) { acc, r in
            guard let want = labels[r.query] else { return acc }
            return r.rankedIds.prefix(k).contains(want) ? acc + 1 : acc
        }
        return Double(hits) / Double(results.count)
    }

    /// Mean reciprocal rank: average of 1/rank of the relevant id (0 when it isn't retrieved at all).
    static func meanReciprocalRank(results: [(query: String, rankedIds: [String])],
                                   labels: [String: String]) -> Double {
        guard !results.isEmpty else { return 0 }
        let total = results.reduce(0.0) { acc, r in
            guard let want = labels[r.query], let idx = r.rankedIds.firstIndex(of: want) else { return acc }
            return acc + 1.0 / Double(idx + 1)
        }
        return total / Double(results.count)
    }

    // MARK: - Built-in smoke corpus

    struct Sample { let id: String; let text: String }

    static let corpus: [Sample] = [
        Sample(id: "thermostat", text: "Hold the power button for ten seconds to reset the thermostat to factory defaults."),
        Sample(id: "wifi", text: "Open the companion app and choose Add Device to connect to your Wi-Fi network."),
        Sample(id: "battery", text: "Replacing the battery needs a Phillips screwdriver and two AA cells."),
        Sample(id: "warranty", text: "The warranty covers parts and labour for two years from purchase."),
        Sample(id: "recipe", text: "Whisk the eggs with sugar, then fold in the flour to make the sponge cake batter."),
        Sample(id: "weather", text: "A cold front brings rain and gusty winds across the coast tomorrow afternoon."),
    ]

    static let queries: [LabeledQuery] = [
        LabeledQuery(query: "how do I factory reset the thermostat", relevantId: "thermostat"),
        LabeledQuery(query: "connect the device to wireless internet", relevantId: "wifi"),
        LabeledQuery(query: "what tools to change the batteries", relevantId: "battery"),
        LabeledQuery(query: "how long is the guarantee", relevantId: "warranty"),
    ]

    /// Embed the corpus with `embedder`, rank each query by cosine, return recall@k over the built-in
    /// labels. Nil when the embedder can't produce vectors (no model available). Side-effect-free
    /// aside from the embedder itself.
    static func selfTest(using embedder: Embedder, k: Int = 1) -> Double? {
        guard embedder.isAvailable else { return nil }
        let vectors = corpus.compactMap { sample in embedder.embed(sample.text).map { (sample.id, $0) } }
        guard !vectors.isEmpty else { return nil }

        let results: [(query: String, rankedIds: [String])] = queries.compactMap { q in
            guard let qv = embedder.embed(q.query) else { return nil }
            let ranked = vectors
                .map { (id: $0.0, sim: Embedder.cosineSimilarity(qv, $0.1)) }
                .sorted { $0.sim > $1.sim }
                .map { $0.id }
            return (q.query, ranked)
        }
        let labels = Dictionary(uniqueKeysWithValues: queries.map { ($0.query, $0.relevantId) })
        return recallAtK(k, results: results, labels: labels)
    }
}
