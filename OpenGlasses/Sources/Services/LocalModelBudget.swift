import Foundation

/// Pure prompt-budget logic for on-device (MLX) generation (BK P2).
///
/// Replaces the old single model-agnostic `maxPromptTokens = 4096` constant. Three problems it
/// fixes:
///  1. **Model-agnostic cap.** A flat 4096 ignored that different models have different real
///     context windows. The budget is now derived per loaded model from a table (with a
///     conservative default for user-typed / unknown ids).
///  2. **No generation headroom.** The old cap let a prompt fill the *entire* window, so
///     prompt + up to 512 generated tokens overflowed *during* generation — relocating the
///     uncatchable per-token OOM from submit-time to mid-stream. The budget subtracts the
///     generation reserve (and a small safety margin).
///  3. **Hard reject with no recovery.** The caller now uses `historyFittingBudget` to trim
///     oldest history first and only throws when even the minimal prompt (system + current turn)
///     overflows.
///
/// No MLX import — deliberately headless-testable.
enum LocalModelBudget {
    /// Tokens reserved for the model's own output. Must match `GenerateParameters(maxTokens:)`
    /// in `LocalLLMService.generate`; if that changes, change this.
    static let generationReserve = 512

    /// Small extra cushion for chat-template scaffolding and count drift between our estimate and
    /// the model's actual tokenization.
    static let safetyMargin = 128

    /// Conservative context window (tokens) for an id we don't recognise. Matches the old flat
    /// cap so unknown / user-typed model ids are no worse off than before — but the budget below
    /// still subtracts the generation reserve, closing the mid-stream-overflow hole.
    static let defaultContextWindow = 4096

    /// Effective (memory-safe) context window per known model id. These are intentionally *below*
    /// each model's theoretical maximum: the on-device ceiling is device memory, not the model's
    /// advertised window. An ~8k-token prompt to a 2B model already Jetsam-killed the app on an
    /// iPhone, so larger models stay at the conservative floor and only the tiny models — which
    /// are cheap to prefill — get more room.
    static let contextWindows: [String: Int] = [
        "mlx-community/Qwen2.5-0.5B-Instruct-4bit": 8192,
        "mlx-community/SmolVLM2-500M-Video-Instruct-mlx": 8192,
        "mlx-community/Qwen2.5-3B-Instruct-4bit": 4096,
        "mlx-community/gemma-2-2b-it-4bit": 4096,
        "mlx-community/gemma-4-e2b-it-4bit": 4096,
        "mlx-community/SmolVLM2-2.2B-Instruct-mlx": 4096,
    ]

    /// Real context window for a model id, or the conservative default for an unknown id.
    static func contextWindow(for modelId: String?) -> Int {
        guard let modelId, let window = contextWindows[modelId] else { return defaultContextWindow }
        return window
    }

    /// Maximum tokenized-prompt length for a model: its window minus the generation reserve and a
    /// safety margin. Never returns less than a small floor so a mis-entered window can't produce a
    /// zero/negative budget that rejects every prompt.
    static func promptBudget(for modelId: String?) -> Int {
        promptBudget(contextWindow: contextWindow(for: modelId))
    }

    /// Budget from an explicit window (unit-test entry point).
    static func promptBudget(contextWindow: Int) -> Int {
        max(minimumBudget, contextWindow - generationReserve - safetyMargin)
    }

    /// Floor so a tiny/misconfigured window still admits the minimal system + turn prompt.
    static let minimumBudget = 512

    /// Trim conversation history so the tokenized prompt fits `budget`, dropping the **oldest**
    /// turns first (the current user turn and system prompt are never dropped). Pure: the caller
    /// injects `tokenCount`, which tokenizes a candidate history the same way the model will.
    ///
    /// Returns the history to actually feed the model. Throws `promptTooLong` only when even an
    /// empty history (system + current turn alone) exceeds the budget — genuine overflow that P2b's
    /// cascade will later route to a bigger-window model.
    static func historyFittingBudget(
        history: [(role: String, content: String)],
        budget: Int,
        tokenCount: (_ history: [(role: String, content: String)]) throws -> Int
    ) throws -> [(role: String, content: String)] {
        var kept = history
        while true {
            let count = try tokenCount(kept)
            if count <= budget { return kept }
            if kept.isEmpty {
                throw LocalLLMError.promptTooLong(tokens: count, limit: budget)
            }
            kept = Array(kept.dropFirst())   // drop the oldest exchange and re-measure
        }
    }
}
