# Plan — Embedding Quality Upgrade (better RAG & memory retrieval)

**Status: 📋 Planned.**

**Builds on:** the [`Embedder`](../../OpenGlasses/Sources/Services/RAG/Embedder.swift) seam, [`DocumentStore`](../../OpenGlasses/Sources/Services/RAG/DocumentStore.swift) (Plan [O](O-document-rag.md)/[P](P-chunk-citations.md)), and [`SemanticMemoryStore`](../../OpenGlasses/Sources/Services/SemanticMemoryStore.swift). This is a **quality upgrade to existing features**, not a new capability.

**Strategic fit:** retrieval quality is the ceiling on "chat with your files" and semantic memory. Stronger, contextual, multilingual embeddings make every RAG answer and every memory recall sharper — and matter most for the multilingual/translation ambitions (live translation, 140+-language personas). Pairs directly with [standalone-chat-experience.md](standalone-chat-experience.md) (doc attachments) and [projects-scoped-contexts.md](projects-scoped-contexts.md).

**Effort:** ~2–3 days.

---

## What already exists (reuse, do not rebuild)

- **`Embedder`** (documents): tries `NLEmbedding.sentenceEmbedding(for:)` first, falls back to averaged `wordEmbedding`; exposes `dimension`, `embed(_:) -> [Float]?`, static `cosineSimilarity`. Instantiated per `DocumentStore` (`Embedder(language: .english)`).
- **`DocumentStore`:** SQLite `documents`/`doc_chunks`, `embedding BLOB`, `namespace` column, `ingest`/`query(limit:namespace:documentIds:)`, cosine over chunks. **No dimension/model stamp** — dimension is implicitly assumed constant.
- **`SemanticMemoryStore`:** the weakest path — embeds with **word-average only** (`NLEmbedding.wordEmbedding(for: .english)`), vectors as BLOB, `namespace` per persona/global. Deliberately kept separate from `Embedder` so a doc-side upgrade doesn't force a memory re-embed.
- **Already-present deps:** `swift-transformers` (1.0.0) + `swift-huggingface` are in `project.base.yml` (tokenizer + Core ML model running). Deployment target is **iOS 26**, so iOS 17+ APIs are available.

## The gap

1. **Static, non-contextual vectors.** `NLEmbedding` word/sentence vectors are lookup-based, English-instance, and weaker than a transformer encoder — averaging word vectors over a 600-char chunk washes out meaning (already flagged as the "one real tradeoff" in Plan O).
2. **`SemanticMemoryStore` is word-average** — the lowest-quality embedding in the app backs the most-used recall path.
3. **No embedding version stamp.** Nothing records *which* model/dimension produced a stored vector. Swapping the model would silently compare incompatible vectors (or crash on dimension mismatch). **This is the real blocker** to any model change and must land first.
4. **The vendored ONNX runtime can't help.** `Vendor/SherpaOnnx` (sherpa-onnx 1.13.3 / onnxruntime 1.26.0) exposes only the high-level TTS (`SherpaOnnxOfflineTtsConfig`) and ASR (`SherpaOnnxOfflineRecognizerConfig`) configs — there is **no generic ONNX inference API**, so we cannot run an `all-MiniLM` ONNX through it. A MiniLM path would go via Core ML, not sherpa.

## New work

**1. Embedding version + migration substrate (do this FIRST — deterministic, testable).**
- Add an `embedding_model` (string id) + `dim` (int) stamp. In `DocumentStore`, a small `meta` table (or columns on `documents`) records the model/dim that produced each chunk's vector; same for `SemanticMemoryStore`.
- A pure `EmbeddingVersion` value + migration policy: on load, if the configured model ≠ the stored model, re-embed (lazily on next access, or eagerly with progress). Pure → table-driven unit tests (no DB).
- This makes every later model swap safe and reversible; without it, the rest is unshippable.

**2. Upgrade `Embedder` to `NLContextualEmbedding` (primary recommendation).**
- `NLContextualEmbedding` (iOS 17+, available on the iOS 26 target) is a transformer encoder with contextual, multilingual-script embeddings — markedly better than `NLEmbedding` for passage retrieval, with **no SPM dep and no model bundle**.
- Make `Embedder` a small strategy/protocol (`embed`, `dimension`, `modelId`) so the active model is swappable and recorded in the version stamp. Keep the current `NLEmbedding` implementation as the fallback when the contextual model/asset isn't available.
- Note: `NLContextualEmbedding` downloads its language asset on first use — handle the "asset not yet present" case (fall back to `NLEmbedding`, fetch in background, re-embed once ready). Record offline implications.

**3. Apply the upgraded `Embedder` to `SemanticMemoryStore`.**
Route memory embedding through the same seam (gated by the migration so existing memory re-embeds). Unifies the two stores on one implementation so future upgrades land in both — now safe because of step 1. Feeds [[project_brain_store]] (`BrainStore.shared.ingest`) with better vectors.

**4. Higher-quality alternative: bundled MiniLM Core ML (optional).**
If `NLContextualEmbedding` quality is insufficient, add an `all-MiniLM-L6-v2` (384-dim) Core ML model behind the same `Embedder` seam, tokenized via the already-present `swift-transformers`. Gives a known, strong, cross-lingual sentence-transformer at the cost of a ~25–90 MB bundle + Core ML inference code. Convert offline with `coremltools`; ship as a bundled asset or first-use download. Behind the version stamp like everything else.

**5. Tiny retrieval benchmark (pure, testable).**
A handful of labelled `query → expected-passage` pairs + a `recall@k` computation to compare `NLEmbedding` vs `NLContextualEmbedding` vs MiniLM offline. Lets the model choice be evidence-based and guards against regressions.

## Build order

1. `EmbeddingVersion` stamp + migration policy (pure) + tests.
2. Wire the stamp into `DocumentStore` (re-embed on mismatch, with progress) — temp-DB tests.
3. `Embedder` strategy protocol; `NLContextualEmbedding` implementation + `NLEmbedding` fallback.
4. Wire `SemanticMemoryStore` through the seam (gated re-embed).
5. Retrieval benchmark; pick the default model from results.
6. (Optional) MiniLM Core ML implementation if the benchmark warrants it.
7. Full suite + **Release** build green before PR.

## Open questions

- **`NLContextualEmbedding` asset download.** It fetches a language asset on first use — confirm size, caching, and the fully-offline fallback path. *Recommendation: fall back to `NLEmbedding` until the asset is present, then re-embed.*
- **Re-embed cost on large stores.** Re-embedding a big doc/memory store is expensive. *Recommendation: lazy re-embed on access + an explicit "re-index now" with progress; never block the UI.*
- **Unify the two stores' embedding code?** *Recommendation: yes, once the version stamp exists* — one `Embedder` seam for both DocumentStore and SemanticMemoryStore.
- **Default model.** *Recommendation: `NLContextualEmbedding` first (zero-bundle, multilingual); promote MiniLM only if the benchmark shows a clear win.*
- **HIPAA.** Embeddings stay strictly on-device, never synced to the gateway (consistent with Plan O).

## Dependencies

- `NaturalLanguage` (system; `NLContextualEmbedding`). Optional MiniLM path: `coremltools` (offline conversion) + a bundled/downloaded Core ML model + `swift-transformers` (already a dep). **Not** sherpa-onnx (TTS/ASR-locked). Reuses the existing raw-sqlite3 + cosine stack.
