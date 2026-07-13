import Foundation

/// Control live translation mode — continuous spoken language translation.
/// Listens to foreign speech, detects the language, translates, and speaks the translation.
struct LiveTranslationTool: NativeTool {
    let name = "live_translate"
    let description = "Start/stop continuous live translation. Listens to spoken foreign language and translates in real-time. Actions: 'start' (begin translating), 'stop' (end session), 'status' (check if active), 'set_language' (set source/target languages)."

    weak var translationService: LiveTranslationService?

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "description": "start, stop, status, or set_language",
                ],
                "source_language": [
                    "type": "string",
                    "description": "Source language code (e.g. 'es' for Spanish, 'ja' for Japanese, 'fr' for French, 'de' for German, 'zh' for Chinese, 'auto' for auto-detect). Default: auto.",
                ],
                "target_language": [
                    "type": "string",
                    "description": "Target language code to translate into (e.g. 'en' for English). Default: en.",
                ],
            ],
            "required": ["action"],
        ]
    }

    func execute(args: [String: Any]) async throws -> String {
        guard let service = translationService else {
            return "Live translation service not available."
        }

        let action = (args["action"] as? String ?? "status").lowercased()
        let source = args["source_language"] as? String ?? "auto"
        let target = args["target_language"] as? String ?? "en"

        switch action {
        case "start":
            if await MainActor.run(body: { service.isActive }) {
                return "Live translation is already running. Say 'stop translating' to end it."
            }
            await service.start(from: source, to: target)
            let sourceName = languageName(source)
            let targetName = languageName(target)
            return "Live translation started: \(sourceName) → \(targetName). I'll translate speech as I hear it. Say 'stop translating' when you're done."

        case "stop":
            await MainActor.run { service.stop() }
            let count = await MainActor.run { service.translationCount }
            return "Live translation stopped. Translated \(count) phrases."

        case "status":
            let active = await MainActor.run { service.isActive }
            if active {
                let detected = await MainActor.run { service.lastDetectedLanguage }
                let count = await MainActor.run { service.translationCount }
                let last = await MainActor.run { service.lastTranslation }
                var status = "Live translation is active. \(count) translations so far."
                if !detected.isEmpty {
                    status += " Last detected language: \(languageName(detected))."
                }
                if !last.isEmpty {
                    status += " Last: \(last.prefix(60))."
                }
                return status
            }
            return "Live translation is not running. Say 'start translating' to begin."

        case "set_language", "language", "set":
            if await MainActor.run(body: { service.isActive }) {
                await MainActor.run { service.stop() }
                await service.start(from: source, to: target)
                return "Switched to \(languageName(source)) → \(languageName(target))."
            }
            return "Translation isn't running. Start it first with the new languages."

        default:
            return "Unknown action '\(action)'. Use: start, stop, status, or set_language."
        }
    }

    private func languageName(_ code: String) -> String {
        let names: [String: String] = [
            "auto": "auto-detect",
            "en": "English", "es": "Spanish", "fr": "French",
            "de": "German", "it": "Italian", "pt": "Portuguese",
            "ja": "Japanese", "zh": "Chinese", "ko": "Korean",
            "ar": "Arabic", "ru": "Russian", "hi": "Hindi",
            "nl": "Dutch", "sv": "Swedish", "da": "Danish",
            "no": "Norwegian", "fi": "Finnish", "pl": "Polish",
            "tr": "Turkish", "th": "Thai", "vi": "Vietnamese",
            "id": "Indonesian", "ms": "Malay", "tl": "Filipino",
        ]
        return names[code] ?? code
    }
}
