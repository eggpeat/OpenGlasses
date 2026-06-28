import Foundation
import NaturalLanguage

/// On-device text embedding for semantic search over document chunks and memory.
///
/// A thin façade over a swappable [[EmbeddingBackend]]: it prefers the transformer
/// `NLContextualEmbedding` ([[NLContextualBackend]]) when enabled and its asset is on-device, and
/// otherwise falls back to `NLEmbedding` ([[NLEmbeddingBackend]] — sentence model preferred, word
/// average otherwise). The active backend is fixed at init, so every vector a given instance produces
/// shares one dimension and `modelId`: queries and stored vectors stay comparable, and a model swap is
/// caught by the version stamp ([[EmbeddingVersion]]) which triggers a re-embed.
struct Embedder {

    let language: NLLanguage
    private let backend: EmbeddingBackend?

    init(language: NLLanguage = .english) {
        self.language = language
        self.backend = Embedder.selectBackend(language: language)
    }

    /// The contextual model when enabled and its asset is present; otherwise the NLEmbedding baseline.
    private static func selectBackend(language: NLLanguage) -> EmbeddingBackend? {
        if Config.contextualEmbeddingEnabled, let contextual = NLContextualBackend.ready(for: language) {
            return contextual
        }
        return NLEmbeddingBackend(language: language)
    }

    /// True if some embedding model is available for the language.
    var isAvailable: Bool { backend != nil }

    /// True when the NLEmbedding **sentence** model backs this instance. False for the word-average
    /// fallback and for the contextual backend (which is better still).
    var usesSentenceModel: Bool { (backend as? NLEmbeddingBackend)?.usesSentenceModel ?? false }

    /// Vector dimension produced by this instance, or 0 if no model is available.
    var dimension: Int { backend?.dimension ?? 0 }

    /// Stable id for the active model — `nl-sentence.<lang>`, `nl-word.<lang>`, or
    /// `nl-contextual.<modelIdentifier>`. Stamps persisted vectors so a model swap re-embeds rather
    /// than silently comparing across embedding spaces. See [[EmbeddingVersion]].
    var modelId: String { backend?.modelId ?? "none.\(language.rawValue)" }

    /// The version stamp (model id + dimension) for vectors this instance produces.
    var version: EmbeddingVersion { EmbeddingVersion(modelId: modelId, dim: dimension) }

    /// Embed text into a vector, or nil if the model can't represent it (or none is available).
    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return backend?.embed(trimmed)
    }

    /// Cosine similarity in [-1, 1]; 0 when dimensions differ or a vector is empty/zero.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = na.squareRoot() * nb.squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    /// Kick off the contextual model's OTA asset download in the background when enabled, so it
    /// becomes the active backend on the next `Embedder()` once present. No-op when disabled or the
    /// asset is already local. Call once at launch.
    static func prepareContextualAssetsIfEnabled(language: NLLanguage = .english) async {
        guard Config.contextualEmbeddingEnabled else { return }
        await NLContextualBackend.prepareAssets(for: language)
    }
}
