import Foundation

/// Quick-fill presets for common self-hosted, OpenAI-compatible LLM servers (siri-and-local-server
/// plan). Picking one prefills the base URL (+ a model hint) so the user doesn't hand-type the
/// host/port. Pure data — fully unit-testable.
enum LocalServerPreset: String, CaseIterable, Identifiable {
    case ollama
    case lmStudio
    case vllm
    case localAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .vllm: return "vLLM"
        case .localAI: return "LocalAI"
        }
    }

    /// Default OpenAI-compatible base URL (chat-completions root) for the server's usual port.
    var baseURL: String {
        switch self {
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .vllm: return "http://localhost:8000/v1"
        case .localAI: return "http://localhost:8080/v1"
        }
    }

    /// What to type in the model field once connected.
    var modelHint: String {
        switch self {
        case .ollama: return "a pulled model, e.g. llama3.2 or qwen2.5"
        case .lmStudio: return "the model currently loaded in LM Studio"
        case .vllm: return "the model passed to --model"
        case .localAI: return "the model name from your LocalAI config"
        }
    }
}
