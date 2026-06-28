import Foundation

/// Identifies the embedding model that produced a stored vector, so vectors from different models are
/// never silently compared (cosine across incompatible spaces) or crashed on a dimension mismatch.
///
/// Stamped alongside every persisted embedding and checked on load. This is the substrate that makes
/// any model swap — `NLEmbedding` (word/sentence) → `NLContextualEmbedding` → a bundled MiniLM —
/// **safe and reversible**: a stored vector whose stamp doesn't match the active model is recomputed
/// rather than misused. See [[Embedder]].
struct EmbeddingVersion: Equatable, Codable {
    /// Stable id for the model+config that produced the vector — e.g. `nl-word.en`, `nl-sentence.en`,
    /// `nl-contextual.en`, `minilm-l6-v2`.
    let modelId: String
    /// Vector dimension. Stored explicitly so a mismatch is caught even if two models shared an id.
    let dim: Int

    init(modelId: String, dim: Int) {
        self.modelId = modelId
        self.dim = dim
    }

    /// Compact round-trippable tag for storing in a single column (`modelId#dim`).
    var tag: String { "\(modelId)#\(dim)" }

    /// Parse a `tag` back into a version. Returns nil for malformed/empty input (an unstamped row).
    init?(tag: String?) {
        guard let tag, let hash = tag.lastIndex(of: "#") else { return nil }
        let id = String(tag[tag.startIndex..<hash])
        guard let dim = Int(tag[tag.index(after: hash)...]), !id.isEmpty else { return nil }
        self.modelId = id
        self.dim = dim
    }
}

/// What to do with a stored vector when the active model differs from the one that produced it.
enum EmbeddingMigrationAction: Equatable {
    /// Stored vector matches the active model — compare as-is.
    case reuse
    /// Stored vector is from another model (or unstamped) — recompute before use.
    case reembed
}

/// Pure decision: compare a stored stamp against the active model's stamp. Headless-testable; no I/O.
enum EmbeddingMigrationPolicy {
    /// True only when a vector stamped `stored` is directly comparable to vectors from `current`.
    /// An unstamped vector (`nil`) is never compatible — legacy rows predate the stamp and must be
    /// re-embedded before they can be trusted.
    static func isCompatible(stored: EmbeddingVersion?, current: EmbeddingVersion) -> Bool {
        stored == current
    }

    /// The action to take for a stored vector given the active model.
    static func action(stored: EmbeddingVersion?, current: EmbeddingVersion) -> EmbeddingMigrationAction {
        isCompatible(stored: stored, current: current) ? .reuse : .reembed
    }
}
