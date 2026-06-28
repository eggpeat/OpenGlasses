import Foundation
import NaturalLanguage

/// A pluggable text-embedding model behind the [[Embedder]] façade. Lets the active model be swapped
/// (NLEmbedding word/sentence → `NLContextualEmbedding` transformer → a future bundled model) without
/// touching the dozens of call sites that just say `Embedder()`. Each backend reports a stable
/// `modelId` so persisted vectors are stamped (see [[EmbeddingVersion]]) and re-embedded on a swap.
protocol EmbeddingBackend {
    var modelId: String { get }
    var dimension: Int { get }
    func embed(_ text: String) -> [Float]?
}

/// The classic on-device path: `NLEmbedding.sentenceEmbedding` (preferred) with an averaged
/// `wordEmbedding` fallback. Lookup-based, non-contextual — the baseline the contextual model improves
/// on. This is the same logic the original `Embedder` shipped; it stays the universal fallback.
final class NLEmbeddingBackend: EmbeddingBackend {
    private let language: NLLanguage
    private let sentenceEmbedding: NLEmbedding?
    private let wordEmbedding: NLEmbedding?

    init?(language: NLLanguage) {
        let sentence = NLEmbedding.sentenceEmbedding(for: language)
        let word = NLEmbedding.wordEmbedding(for: language)
        guard sentence != nil || word != nil else { return nil }
        self.language = language
        self.sentenceEmbedding = sentence
        self.wordEmbedding = word
    }

    var usesSentenceModel: Bool { sentenceEmbedding != nil }
    var dimension: Int { sentenceEmbedding?.dimension ?? wordEmbedding?.dimension ?? 0 }
    var modelId: String { "\(usesSentenceModel ? "nl-sentence" : "nl-word").\(language.rawValue)" }

    func embed(_ text: String) -> [Float]? {
        if let sentence = sentenceEmbedding {
            guard let vec = sentence.vector(for: text) else { return nil }
            return vec.map { Float($0) }
        }
        return wordAverage(text)
    }

    private func wordAverage(_ text: String) -> [Float]? {
        guard let model = wordEmbedding else { return nil }
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        for word in words {
            guard let vec = model.vector(for: word) else { continue }
            for i in 0..<min(vec.count, sum.count) { sum[i] += vec[i] }
            count += 1
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }
}

/// Transformer **contextual** embedding (`NLContextualEmbedding`, iOS 17+). Produces per-token vectors
/// which we mean-pool into one passage vector — markedly better than the lookup-based `NLEmbedding`
/// for retrieval, multilingual, with no SPM dependency.
///
/// The model loads an over-the-air asset on first use, so a backend is only `ready` once
/// `hasAvailableAssets` is true and `load()` succeeds. Loading is expensive, so a loaded model is
/// cached process-wide per language. `prepareAssets` triggers the download in the background; until it
/// lands, [[Embedder]] uses the `NLEmbedding` fallback.
final class NLContextualBackend: EmbeddingBackend {
    private let model: NLContextualEmbedding
    let modelId: String
    var dimension: Int { model.dimension }

    private init(model: NLContextualEmbedding) {
        self.model = model
        self.modelId = "nl-contextual.\(model.modelIdentifier)"
    }

    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let result = try? model.embeddingResult(for: trimmed, language: nil) else { return nil }
        let dim = model.dimension
        var sum = [Float](repeating: 0, count: dim)
        var tokens = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            for i in 0..<min(vector.count, dim) { sum[i] += Float(vector[i]) }
            tokens += 1
            return true
        }
        guard tokens > 0 else { return nil }
        return sum.map { $0 / Float(tokens) }   // mean-pool the token vectors
    }

    // MARK: - Process-wide cache + assets

    private static let lock = NSLock()
    private static var cache: [String: NLContextualBackend] = [:]

    /// A ready-to-use backend for the language, or nil if assets aren't on-device yet (caller falls
    /// back). Loads the model once and caches it; never blocks on a network download.
    static func ready(for language: NLLanguage) -> NLContextualBackend? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[language.rawValue] { return cached }
        guard let model = NLContextualEmbedding(language: language), model.hasAvailableAssets else { return nil }
        do { try model.load() } catch { return nil }
        let backend = NLContextualBackend(model: model)
        cache[language.rawValue] = backend
        return backend
    }

    /// Trigger an OTA asset download for the language if it isn't present. Best-effort; call at launch
    /// when contextual embeddings are enabled so the model becomes available without blocking a query.
    static func prepareAssets(for language: NLLanguage) async {
        guard let model = NLContextualEmbedding(language: language), !model.hasAvailableAssets else { return }
        _ = try? await model.requestAssets()
    }
}
