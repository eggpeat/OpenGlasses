import Foundation

/// The app's top-level operating mode: wake-word direct mode or a realtime streaming session.
enum AppMode: String, CaseIterable {
    case direct = "direct"
    case geminiLive = "geminiLive"
    case openaiRealtime = "openaiRealtime"

    var displayName: String {
        switch self {
        case .direct: return "Direct Mode"
        case .geminiLive: return "Gemini Live"
        case .openaiRealtime: return "OpenAI Realtime"
        }
    }

    var description: String {
        switch self {
        case .direct: return "Wake word, any LLM provider, text-to-speech"
        case .geminiLive: return "Real-time audio/video streaming via Gemini"
        case .openaiRealtime: return "Real-time audio/video streaming via OpenAI"
        }
    }

    /// Whether this mode is a real-time streaming mode (as opposed to wake-word direct mode).
    var isRealtime: Bool {
        self == .geminiLive || self == .openaiRealtime
    }
}
