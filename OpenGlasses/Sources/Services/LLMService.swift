import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Supported LLM providers
enum LLMProvider: String, CaseIterable {
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case groq = "groq"
    case zai = "zai"
    case qwen = "qwen"
    case minimax = "minimax"
    case openrouter = "openrouter"
    case custom = "custom"
    case local = "local"
    case appleOnDevice = "appleOnDevice"

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT)"
        case .gemini: return "Google (Gemini)"
        case .groq: return "Groq"
        case .zai: return "Z.ai (Subscription)"
        case .qwen: return "Qwen (Subscription)"
        case .minimax: return "MiniMax (Subscription)"
        case .openrouter: return "OpenRouter (500+ models)"
        case .custom: return "Custom (OpenAI-compatible)"
        case .local: return "Local (On-Device MLX)"
        case .appleOnDevice: return "Apple Intelligence"
        }
    }

    /// Console URL where users can create/manage API keys.
    var consoleURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .minimax: return URL(string: "https://platform.minimaxi.com")
        case .openrouter: return URL(string: "https://openrouter.ai/keys")
        case .qwen: return URL(string: "https://dashscope.console.aliyun.com/apiKey")
        case .zai, .custom, .local, .appleOnDevice: return nil
        }
    }

    /// Whether this provider uses the OpenAI-compatible API format
    var isOpenAICompatible: Bool {
        switch self {
        case .anthropic, .gemini, .local, .appleOnDevice: return false
        case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom: return true
        }
    }

    /// Default base URL for the provider
    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .zai: return "https://api.z.ai/api/coding/paas/v4/chat/completions"
        case .qwen: return "https://coding-intl.dashscope.aliyuncs.com/v1/chat/completions"
        case .minimax: return "https://api.minimax.io/v1/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .custom: return "https://api.openai.com/v1/chat/completions"
        case .local: return ""
        case .appleOnDevice: return ""
        }
    }

    /// Default model for the provider
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        case .groq: return "llama-3.3-70b-versatile"
        case .zai: return "glm-4.5"
        case .qwen: return "qwen3.5-plus"
        case .minimax: return "MiniMax-M2.7"
        case .openrouter: return "anthropic/claude-sonnet-4"
        case .custom: return "gpt-4o"
        case .local: return "mlx-community/gemma-4-e2b-it-4bit"
        case .appleOnDevice: return "apple-foundation-model"
        }
    }

    /// Whether the base URL field should be shown (editable endpoint)
    var showBaseURL: Bool {
        switch self {
        case .custom, .zai, .qwen, .minimax: return true
        default: return false
        }
    }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .local, .appleOnDevice: return false
        default: return true
        }
    }

    /// Whether this provider supports listing models via API
    var supportsModelListing: Bool {
        switch self {
        case .local, .appleOnDevice: return false
        default: return true
        }
    }
}

/// Unified LLM service supporting Anthropic Claude and OpenAI-compatible APIs.
/// When OpenClaw is configured, includes tool definitions so the LLM can invoke the `execute` tool.
@MainActor
class LLMService: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var activeModelName: String = Config.activeModel?.name ?? "No Model"
    @Published var toolCallStatus: ToolCallStatus = .idle

    /// Last chain-of-thought reasoning from <think> tags (nil if none).
    /// Kept for the Prompt Inspector UI — never spoken aloud.
    @Published var lastReasoning: String?

    /// Optional conversation store — used to persist LLM-generated summaries
    /// when the context window is compressed.
    weak var conversationStore: ConversationStore?

    /// Optional OpenClaw bridge for tool calling in direct mode
    var openClawBridge: OpenClawBridge?

    /// Native tool router — when set, enables built-in tools (weather, timer, etc.)
    var nativeToolRouter: NativeToolRouter?

    /// Plan-then-execute narration hooks (Plan S), wired by AppState to the HUD/TTS. `onAgentNarrate`
    /// gets the plan header; `onAgentStep` gets per-step (index, total, step) progress.
    var onAgentNarrate: ((String) -> Void)?
    var onAgentStep: ((Int, Int, AgentStep) -> Void)?

    /// Local on-device LLM service (MLX Swift)
    var localLLMService: LocalLLMService?


    #if canImport(FoundationModels)
    private var _appleSession: Any?
    @available(iOS 26.0, *)
    private var appleSession: LanguageModelSession? {
        get { _appleSession as? LanguageModelSession }
        set { _appleSession = newValue }
    }
    #endif

    /// Conversation history for multi-turn context.
    /// No artificial turn limit — history persists for the full conversation session.
    /// Context window is managed by token-aware compaction, not a fixed turn count.
    private var conversationHistory: [[String: Any]] = []

    /// Maximum estimated tokens before compacting the context window.
    /// When exceeded, older messages are summarized and compressed rather than dropped blindly.
    private let maxEstimatedTokens = 80_000

    /// Maximum tool call iterations to prevent infinite loops
    private let maxToolCallIterations = 5

    /// Build the full system prompt, optionally including location, tools, memory, and vision context.
    /// When `promptSections` is provided (from the ConversationClassifier), irrelevant sections are
    /// stripped to reduce token count. When nil, all sections are included (backward compatible).
    private static func buildSystemPrompt(locationContext: String?, includeTools: Bool, includeOpenClaw: Bool, hasImage: Bool, nativeToolNames: [String] = [], gatewayToolNames: [String] = [], memoryContext: String? = nil, agentContext: String? = nil, playbookContext: String? = nil, nowPlayingContext: String? = nil, shortcutsContext: String? = nil, promptSections: ConversationClassifier.PromptSections? = nil, turn: String? = nil) async -> String {
        // Agent personality mode: soul.md + skills.md + memory.md replace the standard prompt
        var prompt: String
        if Config.agentModeEnabled, let agentContext, !agentContext.isEmpty {
            prompt = agentContext
        } else {
            prompt = Config.systemPrompt
        }

        // Helper: check if a section should be included. When promptSections is nil (no classifier), include everything.
        let shouldInclude: (ConversationClassifier.PromptSections) -> Bool = { section in
            guard let sections = promptSections else { return true }
            return sections.contains(section)
        }

        // Ensure vision awareness is always present, even if user has a custom system prompt
        if shouldInclude(.vision) && !prompt.lowercased().contains("vision") && !prompt.lowercased().contains("camera") {
            prompt += """

            VISION & CAMERA:
            - The glasses have a camera. When the user says "look at this", "what is this", "read this", "identify this", "take a photo", or similar, a photo will be captured and sent to you automatically.
            - You CAN see images — never say you lack camera or vision access.
            - For text/signs/menus in foreign languages: transcribe the original text, then translate it.
            - For objects, products, landmarks: identify and describe them.
            - After reading text from an image, offer to copy it to clipboard or translate it.
            """
        }

        if includeTools && shouldInclude(.tools) {
            var toolSection = """


            TOOLS:
            You have access to the following tools. Use the appropriate tool when the user's request matches its capability.
            """

            if !nativeToolNames.isEmpty {
                toolSection += "\nBuilt-in tools: \(nativeToolNames.joined(separator: ", "))."
                toolSection += """

            - get_weather: Get current weather and forecast.
            - get_datetime: Get current date, time, day of week.
            - daily_briefing: Combined daily briefing (date, weather, news) — use for "good morning" or "what's happening today".
            - calculate: Evaluate math expressions.
            - convert_units: Convert between units (length, weight, temp, volume, speed, etc).
            - set_timer: Set a countdown timer with local notification.
            - pomodoro: Start/stop/check a Pomodoro focus session (25 min work, 5 min break cycles).
            - save_note / list_notes: Save and retrieve notes locally.
            - web_search: Search the web via DuckDuckGo.
            - get_news: Get latest news headlines, optionally by topic.
            - translate: Translate text between languages.
            - translate_sign_menu: Translate visible signs/menus from camera view. Returns ORIGINAL text first, then translation.
            - ask_local_phrase: Generate traveler phrases in the local language with pronunciation and a polite variant.
            - define_word: Look up word definitions.
            - find_nearby: Search for nearby places (restaurants, cafes, pharmacies, gas stations, etc).
            - where_am_i: Describe the user's current location with reverse-geocoded place context and GPS coordinates.
            - open_app: Open iOS apps (Music, Podcasts, Maps, Google Maps, YouTube, Spotify, etc).
            - get_directions: Directions via Apple Maps or Google Maps (set app='google' for Google Maps).
            - identify_song: Identify a song playing nearby using Shazam.
            - music_control: Play, pause, skip, previous track, or get now-playing info (Apple Music).
            - convert_currency: Convert between currencies with live exchange rates.
            - phone_call: Make a phone call to a number.
            - send_message: Open Messages with a pre-filled text to a recipient.
            - copy_to_clipboard: Copy text to clipboard (great after OCR, translation, or any result the user wants to keep).
            - flashlight: Turn the device flashlight on/off.
            - device_info: Check battery level, storage, and low power mode.
            - save_location / list_saved_locations: Save current spot with a label ("remember where I parked") and find saved spots later with distance.
            - step_count: Today's steps, walking distance, and floors climbed.
            - emergency_info: Local emergency numbers for current country, exact GPS coordinates, and guidance to find nearest hospital.
            - calendar: View today's schedule, next meeting, upcoming week, or create events. Events get a 15-min reminder notification.
            - lookup_contact: Look up a contact by name to get their phone number or email. Use before phone_call or send_message.
            - reminder: Create, list, or complete Apple Reminders with due dates and notifications. Syncs with iCloud.
            - set_alarm: Set an alarm for a specific clock time (e.g. '7 AM tomorrow'). Also list or cancel alarms.
            - brightness: Adjust screen brightness (0-100, or presets: max, min, dim, bright, up, down).
            - smart_home: Control HomeKit smart home devices — lights, switches, fans, thermostats, locks, scenes. ALWAYS try this tool for smart home requests. Say 'list' to see devices.
            - run_shortcut: Run an Apple Shortcut by name (e.g. 'Start Focus', 'Log Water', any user-created shortcut).
            - summarize_conversation: Summarize current conversation, extract action items/to-dos. Use when user says "summarize", "recap", or "what did we discuss?"
            - face_recognition: Remember faces ('remember this person as John'), forget faces, list known people, or toggle auto-recognition on/off.
            - memory_rewind: Recall what was said recently. Transcribes last few minutes of ambient audio. Use for "what did they just say?" or "what happened?" Must be started first with action='start'.
            - geofence: Location-based reminders. 'Remind me when I get to the office' or 'alert me when I leave home'. Create, list, delete geofenced alerts.
            - send_via: Send messages via WhatsApp, Telegram, or Email. Specify channel ('whatsapp', 'telegram', 'email'), recipient, and body.
            - meeting_summary: Summarize a recent meeting or conversation from ambient captions. Extracts key points, decisions, and action items. Requires ambient captions to be running.
            - fitness_coach: Fitness coaching — start/stop workouts, log exercises (reps/sets/weight), check form via camera, get workout history from HealthKit, set step goals.
            - openclaw_skills: Discover and manage OpenClaw skills. List available skills, check gateway status, search for capabilities. Only available when OpenClaw is configured.
            - voice_skills: Voice-taught skills — save (teach a new trigger→action), list (show all), delete, clear. "Learn that when I say 'goodnight', turn off all lights."
            - object_memory: Remember where physical objects are. Save ('remember my keys are on the counter'), find ('where are my keys?'), list, forget.
            - contextual_note: Save notes with automatic location and time context. Search notes by keyword or location.
            - social_context: Remember facts about people. Add facts ('remember John works at Stripe'), recall ('what do I know about John?'), list people.
            - brain: Unified search across ALL on-device memory (facts, documents, people, notes, meetings, knowledge graph + encounter log). action 'query' for any "what do I know about…" when unsure where it lives; 'recall' to search PAST CONVERSATIONS — what you actually said in earlier sessions — and get a cited answer ("what did we decide about X?", "what did I say about Y last week?"); 'insights' for an on-device usage recap — top topics + activity over the last N days ("what have I been up to this week?"); 'person' for a dossier before/after meeting someone ("brief me on Alice"); 'link' to record relationships ('Alice works at Acme'); 'encounters' for recent sightings ("when did I last see Bob?"); 'save_need' for a follow-up ("Bob wants the deck"), 'needs' to list open follow-ups, 'resolve_need' to close one. Cites sources and says what's missing — answer only from its findings.
            - home_assistant: Control Home Assistant smart home — toggle devices, check states, list entities, run automations, or use 'converse' action to send natural language commands directly to HA (e.g. action=converse, text="turn on the kitchen lights"). ALWAYS try this tool when asked about smart home control. Use entity IDs from the device list below when available; the tool also fuzzy-matches and falls back to HA's voice assistant.
            - vehicle_status: Get the user's vehicle / EV charge %, range, charging state, and plug status. Reads live from Home Assistant — use for "what's my car's charge?", "is the car charging?", "how much range do I have?".
            - scan_code: Scan QR codes or barcodes from the camera. Returns decoded content (URLs, text, product codes). Works offline.
            - capture_photo: Capture a photo from the glasses camera for visual analysis. Use when you need to see what the user is looking at, or proactively when visual context would help your response.
            - reading_assist: Read text in front of the user via the glasses camera (on-device OCR). Modes: read (clean + read aloud), simplify (rewrite at a reading level 1-5), translate (into target_language), define (plain-language definition of a term). Use for 'read this to me', 'simplify this', 'translate this sign', 'what does this word mean'.
            - health_vault: Query or update the user's Personal Health Vault (their own notes on biometrics, conditions, diet, labs, medications, wearables). action 'query' (with question) grounds a health question in their data — cite the source file; action 'log' (file + entry) records a new entry. Never fabricate health data.
            - health_check: "Is this safe for ME?" over the Health Vault. 'can_i_take' a medication/supplement ("can I take ibuprofen?") or 'can_i_eat' a food ("can I eat aged cheese?"). Cross-references known high-severity drug/food interactions deterministically against the user's meds/conditions/allergies. Advisory only; always cites the vault and defers to a pharmacist/doctor. Param: subject.
            - notes_vault: The user's personal notes / second brain. 'log' to remember something ("note that…", "remember…"), 'query' to recall it ("what did I note about…"). Files: general, people, ideas, todos. Answers only from recorded notes.
            - document_knowledge: Private on-device knowledge base of the user's documents (manuals, contracts, reports). action 'query' retrieves the most relevant passages to ground an answer — cite the document name and answer only from what's returned; 'ingest_scan' captures and saves a document seen through the glasses ("remember this manual"); 'ingest_text' saves provided text; 'list' shows saved documents; 'forget' deletes one. Use 'query' whenever the user asks about a document they've saved.
            - study: Study Mode — turn a document into flashcards + a quiz and review hands-free with spaced repetition. Actions: scan (OCR a page through the glasses camera; repeat then make_deck), make_deck (from scanned pages, a document name via 'deck', or raw 'text'), list, quiz (start), answer (via 'value' — a number or the option), review (flashcards), flip, grade (right/wrong via 'value'), stop. Use for "study this page", "make flashcards from X", "quiz me".
            - identify_medication: Read a medication label via the glasses camera (on-device OCR) and cross-check it against the user's recorded medications. Use for "what's this pill?", "is this my medication?". Reports the label text + match status; never makes clinical claims. Needs Medical Compliance.
            - aircraft_overhead: Report aircraft flying near the user using live ADS-B data and their location. Use for "what's flying overhead?", "any planes nearby?". Param: radius_miles (1-200, default 25).
            - live_coach: Real-time, one-sentence coaching feedback from the glasses camera. Use for "coach my squat form", "watch my knife technique", "help with my guitar". Actions: start (domain), stop, status. Domains: sports_tactics, cooking_form, posture, guitar, climbing, custom. Params: custom_prompt, interval_seconds, max_words, max_duration_minutes.
            - code_agent: Hands-free control of a REMOTE coding agent (runs on the user's gateway, not the phone). Use for "have the agent add a dark-mode toggle", "ask the agent to fix the failing test". Actions: start (prompt, optional project), status, cancel, confirm, deny. Requires Agent Mode enabled in Settings. Progress and a final summary are spoken.
            - network_calc: IP subnet/CIDR math for IT field work. operation 'subnet' with a 'cidr' (IPv4 or IPv6) returns network, broadcast, netmask, usable host range and count. Use for subnetting questions.
            - navigation_assist: Spoken walking guidance for low-vision users — periodically calls out hazards/landmarks (steps, drop-offs, obstacles, oncoming people) using clock positions. Actions: start, stop, status. Use for "guide me", "navigation mode". An aid, not a cane/guide-dog replacement.
            - first_aid: Hands-free first-aid coaching in an emergency — speaks step-by-step guidance and paces CPR with a metronome. Actions: start (protocol: cpr, choking, bleeding, recovery, march), next, back, aed (find nearest defibrillator), stop. Use for "start CPR", "someone is choking", "they're bleeding", "nearest AED". Advisory only — always reminds the user to call emergency services; not a substitute for professional care.
            - identify_color: Name the dominant color of what the user is looking at (on-device, no network). Use for "what color is this?".
            - identify_money: Identify a banknote's currency and denomination from the glasses camera, for low-vision support. Use for "how much is this note?", "what bill is this?".
            - audio_recording: Start or stop audio-only recording (no camera — lighter on battery). Saves .m4a to Documents/Recordings with live transcription and a meeting assistant that sends lock screen summaries + suggested questions every 60 seconds. Saying 'take a picture' during recording adds a visual note to the transcript. Actions: start, stop, status. Use when the user says 'record this meeting', 'record audio', 'record this conversation', or 'start audio recording'.
            - video_recording: Start or stop video+audio recording from the glasses camera and microphone. Recordings save to Photos with no time limit — ideal for interviews, meetings, procedures. Includes live transcription by default (saved as .txt alongside video). Actions: start, stop, status. Params: transcribe (bool, default true). Use when the user says 'start recording', 'record this', 'film this', 'watch what I'm doing', or 'stop recording'.
            - medical_export: Export clinical transcripts to medical platforms or share manually. Actions: export_fhir (upload to FHIR server), export_file (create file), share (open share sheet), status (check config). Params: format (text/pdf/fhir_json/hl7), transcript (optional, uses latest recording). Use when the user says 'export the transcript', 'send to the EMR', 'share the notes', or 'upload to the health record'.
            - qr_context: Scan a QR code and load its content as context (museum exhibits, venue info, procedures). Use at museums, venues, or workplaces. Can also load context from a URL directly.
            - smart_capture: Capture a business card, receipt, or event flyer and extract structured details (mode: contact/receipt/event). Then chain to contacts/calendar/notes_vault to act. Use for "save this card", "log this receipt", "add this event from the flyer".
            - vision_assess: Run a structured visual assessment of what the glasses camera sees and show a typed result card (kind selects the assessment). Use kind 'instrument_reading' to read a number off a gauge, thermometer, refractometer, scale, or meter ("what does this gauge read?", "read the thermometer"). Optional note adds context.
            - golf_mode: Golf caddy assistant — track shots with GPS, get club recommendations, log scores, view round summary, and get course strategy. Actions: start_round, track_shot, club_recommendation, log_score, round_summary, strategy.
            - live_translate: Start/stop continuous live translation. Listens to spoken foreign language and translates in real-time. Actions: start, stop, status, set_language.
            - field_session: Start, pause, resume, end, or query a Field Assist session for grounded, domain-specific technical support (refrigeration, IT, electrical, automotive). Sessions load a domain knowledge vault and emit an audit log. Use 'start' when the technician begins work, 'end' when they finish, 'export' to generate a work-order PDF + audit JSON. Actions: start, pause, resume, end, status, list, escalate, export. Params: vault (e.g. 'refrigeration'), asset_id, mode ('ai_only' default), outcome, reason, format ('pdf'/'json'/'both').
            - procedure_runner: Run a guided, step-by-step Field Assist procedure (diagnostics, checklists) inside an active session. Actions: list, start, next, previous, repeat, status, complete. When the active step offers choices, pass 'choice' with the branch id to 'next'. The current step and its choice ids are injected into this prompt under "ACTIVE PROCEDURE" — use those. Params: procedure_id, choice, outcome.
            - project_note: Notes scoped to the ACTIVE field job — what the user is mid-way through. 'save' records a note about the current job ("compressor swap is next"); it surfaces automatically on later turns while the job is active. 'list' shows the job's notes; 'clear' removes them. For in-progress job state, not durable user facts. Params: text.
            - capture_flow: Run a structured, typed capture flow (inspection / work-order form) inside an active session — each step collects a validated value (reading, enum choice, barcode, or photo) bound to a field, producing an audit-ready record. Actions: list, start, answer, skip, back, status, finish, cancel. After 'start', read the returned step prompt to the user; pass their spoken value verbatim to 'answer'. The runner range-checks numbers, maps spoken phrases to enum options, and re-prompts on a bad answer; 'finish' blocks until required fields are captured. Params: flow_id, asset_id, value.
            - domain_calc: Refrigeration math grounded in the vault PT charts. Operations: pt_lookup (saturation temp at a pressure), superheat (suction line temp − sat temp at suction pressure), subcool (sat temp at liquid pressure − liquid line temp). Temps °F, pressures PSIG. Params: operation, refrigerant ('R-410A','R-32','R-454B','R-22'), pressure_psig, suction_pressure_psig, suction_line_temp_f, liquid_pressure_psig, liquid_line_temp_f.
            - equipment_lookup: Look up an error code, fault, or model number in the active session's vault. The technician can read it aloud (query), or point the glasses at the nameplate/error display and omit query (or set use_camera) to read it via on-device OCR. Returns the matching reference section with its source. Params: query (optional), use_camera (optional bool), file (optional).
            - safety_assessment: Run a High-Energy Control Assessment (HECA) on the current job-site view from the glasses camera — detects the 13 high-energy serious-injury/fatality hazards and whether each has a DIRECT control, and returns a summary + HECA score. Use for "assess this site", "is this safe?", "safety check". Actions: run, last, score, history, export (PDF of the latest report), ask (image-seeded safety-advisor follow-up — pass question). Advisory only — verify on site; not a certified inspection.
            - photo_log: Capture a photo from the glasses camera and attach it to the active session's audit log with a caption (e.g. a gauge reading), and return the image for analysis. Use to document readings and evidence during a session. Params: caption.
            - escalate_to_expert: Escalate the active Field Assist session to a human expert when you cannot safely resolve the issue or the technician asks for a person. Actions: request (with reason), status, resolve, cancel. Live expert video is not available yet — escalation is logged and the expert pool is notified.
            - teleprompter: Hands-free teleprompter on the in-lens HUD — shows a script a window at a time and (audio-paced) auto-advances by listening to you read. Actions: start (text=the script, or script=a saved script name, or document=a saved knowledge-base document; optional mode audio_paced/voice/auto_scroll), stop, pause, resume, next, back, restart, faster, slower, list (saved scripts), save (text + optional title), scan (capture a printed page via the glasses camera + OCR — repeat for multiple pages, then start). Use for "start the teleprompter", "read my speech", "teleprompt my saved doc", "scan this script", "go faster/slower".
            """

                // Inject user-defined custom tool descriptions
                let customTools = Config.customTools.filter { Config.isToolEnabled($0.name) }
                for ct in customTools {
                    toolSection += "\n            - \(ct.name): \(ct.description)"
                }

                // Inject the user's Siri Shortcuts so run_shortcut targets real names (Plan Z)
                if let shortcuts = shortcutsContext {
                    toolSection += "\n\n            \(shortcuts.replacingOccurrences(of: "\n", with: "\n            "))"
                }

                // Inject Home Assistant device list so LLM uses real entity IDs (skip if classifier says not needed)
                if shouldInclude(.homeAssistant),
                   let haSummary = await HomeAssistantEntityCache.shared.deviceSummaryForPrompt() {
                    toolSection += "\n\n            \(haSummary.replacingOccurrences(of: "\n", with: "\n            "))"
                }
            }

            if includeOpenClaw && shouldInclude(.openClaw) {
                toolSection += """

            OPENCLAW GATEWAY:
            You also have an "execute" tool that connects to OpenClaw — a powerful personal assistant \
            running on the user's computer. It has access to their files, browser, apps, messages, \
            notes, calendar, contacts, and everything on their machine. It knows things about the \
            user that you don't.
            \(!gatewayToolNames.isEmpty ? "\nAvailable gateway skills: \(gatewayToolNames.joined(separator: ", ")).\nUse execute with the matching skill name for these capabilities." : "")
            Use execute when:
            - Built-in tools can't handle the request
            - The user asks about personal info, preferences, or history you don't have
            - Sending messages on any platform (WhatsApp, Telegram, Slack, email, etc.)
            - Complex research, drafting, or multi-step tasks
            - Controlling apps, services, or external integrations
            - Remembering or recalling anything beyond your conversation context

            NEVER say "I don't know anything about you" — ask OpenClaw via execute instead. \
            If you're unsure whether you can handle something, use execute. It's your extension.
            """
            }

            toolSection += """

            TOOL USAGE RULES:
            CRITICAL: NEVER tell the user a tool is "not configured" or "not set up" — ALWAYS call the tool and let it handle errors. The tools check configuration internally and return helpful messages. Your job is to call them, not to guess their state.
            1. ALWAYS speak a brief verbal acknowledgment BEFORE calling any tool. This prevents awkward \
            silence while the tool executes. Examples:
               - "Sure, let me check the weather." then call get_weather.
               - "Got it, searching for that now." then call web_search.
               - "One moment, looking that up." then call web_search.
            2. CONTACTS: phone_call and send_message both accept contact NAMES directly (e.g. "Mom", "John"). \
            They automatically resolve names to phone numbers from the user's contacts. You do NOT need to call \
            lookup_contact first — just pass the name. If multiple matches exist, the tool returns options for the user to choose. \
            Only use lookup_contact when the user explicitly asks "what's someone's number?" without wanting to call or text.
            3. MULTI-STEP CHAINS: You can call multiple tools in sequence. After receiving a tool result, \
            you may call another tool before responding. Examples:
               - "Call the nearest pharmacy" → find_nearby (find pharmacy) → phone_call (call the number)
               - "How do I get to John's house?" → lookup_contact (get address) → get_directions (navigate)
               - "Save what that sign says" → (read image text) → copy_to_clipboard (save it)
            4. The calendar proactive alert system will automatically notify the user 10 minutes before events. \
            You do NOT need to remind them about upcoming events unless they ask.
            5. FALLBACK TO OPENCLAW: If a built-in tool fails or you don't have the info the user needs, \
            use execute (OpenClaw). It has 56+ skills and access to the user's full computer. \
            NEVER tell the user something can't be done or that you don't know — try OpenClaw first.
            """

            prompt += toolSection
        }
        if hasImage {
            prompt += """


            VISION INPUT:
            This turn includes an image captured from the user's glasses camera. You can analyze that image for this response.
            Do not say you lack camera or image access when an image is attached. If the image is unclear, say what you can and cannot make out.

            IDENTIFY & OCR:
            When the user asks to "identify", "read", "OCR", or "what does this say", carefully read ALL text visible in the image.
            - For signs, menus, labels, documents: transcribe the text accurately.
            - For foreign language text (e.g. Japanese, Chinese, Korean, Arabic, etc.): first transcribe the original text, then provide a translation into the user's language (English by default). Format as: "[Original text] — [Translation]".
            - For objects, products, landmarks: describe what you see and identify it.
            - For barcodes/QR codes: note their presence even if you can't decode them.
            """
        }
        if let memory = memoryContext {
            prompt += "\n\n\(memory)"
            prompt += """


            MEMORY INSTRUCTIONS:
            You can remember facts about the user by including [REMEMBER: key = value] in your response.
            You can forget facts with [FORGET: key]. These tags will be stripped before speaking.
            Memories persist across all conversations — they are the bridge between sessions.

            What to remember: names, preferences, family members, routines, interests, important dates, relationships, stated goals.
            Only remember when the user explicitly shares personal info — don't infer or assume.

            Memory hygiene — keep memory accurate and compact:
            - Before adding a fact, check the existing memories listed above. If one already covers that key, update it rather than creating a duplicate.
            - Merge related facts when possible (e.g. "partner = Alex" plus "Alex's birthday is March 5" → update partner entry to include both).
            - For time-sensitive facts (e.g. "at the airport", "working on a presentation"), include a date or context so staleness can be evaluated later.
            - Use [FORGET: key] to remove facts the user corrects or that are clearly no longer true.
            - When the user says "forget X" or "that's wrong", always issue a [FORGET] command before storing the correction.
            """
        }
        if let playbook = playbookContext {
            prompt += "\n\n\(playbook)"
        }
        if let location = locationContext {
            prompt += "\n\nUSER LOCATION: \(location)"
        }
        if let nowPlaying = nowPlayingContext {
            prompt += "\n\n\(nowPlaying)"
        }
        // Inject voice-taught skills
        if shouldInclude(.tools), let skills = VoiceSkillStore.shared.promptContext(for: turn) {
            prompt += "\n\n\(skills)"
        }
        // Inject Field Assist vault content when a session is active.
        // This grounds the LLM in domain knowledge (refrigeration, IT, health) with strict source attribution.
        if let vaultContext = FieldSessionService.shared.promptContext() {
            prompt += "\n\n\(vaultContext)"
        }
        // Inject the active project's knowledge-base grounding when it has documents (Plan AN).
        if let projectContext = ProjectContextService.shared.promptContext() {
            prompt += "\n\n\(projectContext)"
        }
        // Inject project-scoped notes for the active job (what the user is mid-way through).
        if Config.projectMemoryEnabled,
           let session = FieldSessionService.shared.activeSession, session.isActive {
            let eligible = ProjectMemoryScope.eligible(
                BrainStore.shared.projectMemories(for: session.id), activeProject: session.id)
            let block = ProjectMemoryFormatter.block(eligible)
            if !block.isEmpty { prompt += "\n\n\(block)" }
        }
        // Inject social context (people the user knows)
        if shouldInclude(.social), let social = SocialContextStore.shared.promptContext() {
            prompt += "\n\n\(social)"
        }
        // Inject installed ClawHub skills
        if shouldInclude(.openClaw), let skillContext = InstalledSkillStore.shared.promptContext(for: turn) {
            prompt += "\n\n\(skillContext)"
        }
        // Always append the prompt-injection / untrusted-content policy. This is a security
        // baseline — it is never stripped by the classifier and applies in every mode.
        prompt += PromptInjectionPolicy.systemPromptPolicy
        return prompt
    }

    /// Frame a tool result before feeding it back to the model. Output from tools that return
    /// untrusted external content (web, OCR, captions, gateway, MCP, …) is wrapped in a labelled
    /// envelope so injected instructions inside it are visibly framed as data, not commands.
    private func wrapToolResultForModel(toolName: String, content: String) -> String {
        let isKnownNative = nativeToolRouter?.registry.tool(named: toolName) != nil
        guard PromptInjectionPolicy.isUntrustedOutput(toolName: toolName, isKnownNativeTool: isKnownNative) else {
            return content
        }
        return PromptInjectionPolicy.wrap(toolName: toolName, content: content)
    }

    /// - Parameter onToken: optional per-token callback for streaming the final assistant reply
    ///   into the UI as it's generated. Currently honoured by the on-device (`local`) provider;
    ///   cloud providers ignore it and return the full reply on completion.
    func sendMessage(_ text: String, locationContext: String? = nil, imageData: Data? = nil, memoryContext: String? = nil, agentContext: String? = nil, playbookContext: String? = nil, nowPlayingContext: String? = nil, shortcutsContext: String? = nil, promptSections: ConversationClassifier.PromptSections? = nil, onToken: ((String) -> Void)? = nil) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        // Compress context window if conversation history has grown too large
        // Use LLM summarization in agentic mode, heuristic fallback otherwise
        if Config.agentModeEnabled {
            await compressContextWindowWithLLM()
        } else {
            compressContextWindowIfNeeded()
        }

        guard let modelConfig = Config.activeModel else {
            throw LLMError.missingAPIKey("No model configured — add one in Settings")
        }

        let provider = modelConfig.llmProvider
        let hasNativeTools = nativeToolRouter != nil
        let includeOpenClaw = Config.isOpenClawConfigured && openClawBridge != nil
        let includeTools = hasNativeTools || includeOpenClaw
        let nativeToolNames = nativeToolRouter?.registry.toolNames ?? []
        let gatewayToolNames = openClawBridge?.availableToolNames ?? []
        let fullPrompt = await Self.buildSystemPrompt(locationContext: locationContext, includeTools: includeTools, includeOpenClaw: includeOpenClaw, hasImage: imageData != nil, nativeToolNames: nativeToolNames, gatewayToolNames: gatewayToolNames, memoryContext: memoryContext, agentContext: agentContext, playbookContext: playbookContext, nowPlayingContext: nowPlayingContext, shortcutsContext: shortcutsContext, promptSections: promptSections, turn: text)

        var toolsLabel = ""
        if hasNativeTools { toolsLabel += " [NativeTools]" }
        if includeOpenClaw { toolsLabel += " [OpenClaw]" }
        print("🤖 Using model: \(modelConfig.name) (\(modelConfig.model) via \(provider.displayName))\(toolsLabel)")

        // Plan-then-execute (Plan S): for a multi-step request in agent mode, plan deliberately and
        // run each step through the supervisor-gated router, instead of the single-shot tool loop.
        // The planner sees the request alone (not chat history), and tool output never re-enters
        // planning — the structural prompt-injection defense. Falls back to single-shot when the
        // request can't be planned/validated (still safe; every call is supervised either way).
        if Config.agentModeEnabled, hasNativeTools, imageData == nil, await classifyMultiStep(text) {
            if let summary = await runAgentPlan(request: text, nativeToolNames: nativeToolNames) {
                conversationHistory.append(["role": "user", "content": text])
                conversationHistory.append(["role": "assistant", "content": summary])
                trimHistory()
                return summary
            }
            print("🧭 Agent plan loop yielded no plan — falling back to single-shot")
        }

        let rawResponse: String
        switch provider {
        case .anthropic:
            rawResponse = try await sendAnthropic(text, systemPrompt: fullPrompt, config: modelConfig, includeTools: includeTools, imageData: imageData, onToken: onToken)
        case .gemini:
            rawResponse = try await sendGemini(text, systemPrompt: fullPrompt, config: modelConfig, includeTools: includeTools, imageData: imageData)
        case .local:
            rawResponse = try await sendLocal(text, systemPrompt: fullPrompt, config: modelConfig, includeTools: includeTools, imageData: imageData, onToken: onToken)
        case .appleOnDevice:
            rawResponse = try await sendAppleOnDevice(text, systemPrompt: fullPrompt)
        case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
            rawResponse = try await sendOpenAICompatible(text, systemPrompt: fullPrompt, config: modelConfig, includeTools: includeTools, imageData: imageData, onToken: onToken)
        }

        // Strip <think> tags: keep reasoning in history but don't speak it
        if Config.agentModeEnabled {
            let (spoken, reasoning) = Self.stripThinkTags(rawResponse)
            lastReasoning = reasoning
            if let reasoning {
                NSLog("[LLMService] Think: %@", String(reasoning.prefix(200)))
            }
            return spoken
        }

        lastReasoning = nil
        return rawResponse
    }

    // MARK: - Plan-then-execute (Plan S)

    /// Decide whether to route `text` through the plan-then-execute loop (Plan S Phase 2).
    /// The pure keyword heuristic decides for free; when the LLM classifier is enabled and
    /// the request is ambiguous (`ComplexityClassifier.shouldConsultLLM`), a tiny history-free
    /// completion breaks the tie. Any classifier failure falls back to the heuristic.
    private func classifyMultiStep(_ text: String) async -> Bool {
        let heuristic = AgentComplexity.isMultiStep(text)
        guard Config.llmComplexityClassifierEnabled,
              ComplexityClassifier.shouldConsultLLM(text) else {
            return heuristic
        }
        let verdict = (try? await completeStateless(text, system: ComplexityClassifier.systemPrompt))
            .flatMap(ComplexityClassifier.parseVerdict)
        return ComplexityClassifier.decide(heuristic: heuristic, llmVerdict: verdict) == .multiStep
    }

    /// Plan a multi-step request, validate it, and run each step through the supervisor-gated
    /// router. Returns the spoken summary, or nil to fall back to the single-shot tool loop.
    private func runAgentPlan(request: String, nativeToolNames: [String]) async -> String? {
        guard let router = nativeToolRouter else { return nil }
        let mcpNames = router.mcpClient?.discoveredTools.filter { $0.trust.isOffered }.map(\.qualifiedName) ?? []
        let available = nativeToolNames + mcpNames
        guard !available.isEmpty else { return nil }

        let planner = AgentPlanner()
        planner.complete = { [weak self] req, sys in
            guard let self else { return "" }
            return try await self.completeStateless(req, system: sys)
        }
        let runner = AgentRunner(router: router, planner: planner)
        runner.onNarrate = { [weak self] line in self?.onAgentNarrate?(line) }
        runner.onStep = { [weak self] index, total, step in self?.onAgentStep?(index, total, step) }

        guard let result = await runner.run(request: request, availableTools: available) else { return nil }
        NSLog("[LLMService] Agent plan ran %d/%d steps (aborted=%@)",
              result.completedSteps, result.totalSteps, result.aborted ? "yes" : "no")
        return result.summary
    }

    /// A stateless, tools-off completion for the planner: it sees only the system prompt + the
    /// request, never the live conversation history (planning must use trusted context only, and
    /// must not pollute the chat). History is snapshotted and restored even on error.
    /// Stateless, tool-free completion against the user's active provider (honors on-device
    /// models). Used by lightweight features like recall summarization.
    func completeStateless(_ text: String, system: String) async throws -> String {
        guard let config = Config.activeModel else {
            throw LLMError.missingAPIKey("No model configured")
        }
        let snapshot = conversationHistory
        conversationHistory = []
        defer { conversationHistory = snapshot }

        switch config.llmProvider {
        case .anthropic:
            return try await sendAnthropic(text, systemPrompt: system, config: config, includeTools: false, imageData: nil)
        case .gemini:
            return try await sendGemini(text, systemPrompt: system, config: config, includeTools: false, imageData: nil)
        case .local:
            return try await sendLocal(text, systemPrompt: system, config: config, includeTools: false, imageData: nil)
        case .appleOnDevice:
            return try await sendAppleOnDevice(text, systemPrompt: system)
        case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
            return try await sendOpenAICompatible(text, systemPrompt: system, config: config, includeTools: false, imageData: nil)
        }
    }

    /// Clear conversation history (e.g. when starting fresh or switching providers)
    func clearHistory() {
        conversationHistory.removeAll()
    }

    /// Load a persisted conversation thread into the in-memory history.
    /// Called when the user resumes a past conversation from the history view.
    /// The full thread is loaded and then compacted if it exceeds the token budget,
    /// preserving key signals from earlier messages.
    func loadConversationHistory(_ messages: [(role: String, content: String)]) {
        conversationHistory.removeAll()
        for msg in messages {
            conversationHistory.append(["role": msg.role, "content": msg.content])
        }
        // Compact immediately if the restored history is too large for the context window
        compressContextWindowIfNeeded()
        NSLog("[LLM] Loaded %d messages from conversation history (%d after compaction)",
              messages.count, conversationHistory.count)
    }

    /// Compress the context window when estimated token count exceeds the budget.
    ///
    /// Instead of blindly dropping oldest messages, this uses structured compaction:
    /// 1. Extracts key signals from messages about to be removed (decisions, names, memory commands, topics)
    /// 2. Creates a compact summary message that preserves those signals
    /// 3. Replaces the old messages with the summary + keeps recent context intact
    ///
    /// This ensures the agent doesn't "forget" mid-conversation decisions or user facts
    /// even as the raw message history is trimmed for token budget.
    private func compressContextWindowIfNeeded() {
        let estimatedTokens = conversationHistory.reduce(0) { total, msg in
            let content: String
            if let text = msg["content"] as? String {
                content = text
            } else if let parts = msg["content"] as? [[String: Any]] {
                // Multi-part content (images + text)
                content = parts.compactMap { $0["text"] as? String }.joined()
            } else {
                content = ""
            }
            // ~4 chars per token, minimum 50 for overhead (tool calls, images)
            return total + max(content.count / 4, 50)
        }

        guard estimatedTokens > maxEstimatedTokens, conversationHistory.count > 6 else { return }

        let originalCount = conversationHistory.count

        // Keep the most recent messages (at least 6 to preserve current thread)
        let keepCount = max(6, conversationHistory.count / 3)
        let messagesToCompress = Array(conversationHistory.prefix(conversationHistory.count - keepCount))
        let messagesToKeep = Array(conversationHistory.suffix(keepCount))

        // Extract key signals from the messages we're about to compress
        var signals: [String] = []
        for msg in messagesToCompress {
            let role = msg["role"] as? String ?? ""
            let content: String
            if let text = msg["content"] as? String {
                content = text
            } else if let parts = msg["content"] as? [[String: Any]] {
                content = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
            } else {
                continue
            }

            // Preserve memory commands (they represent decisions the agent made)
            if content.contains("[REMEMBER") || content.contains("[FORGET") {
                let memoryLines = content.components(separatedBy: "\n")
                    .filter { $0.contains("[REMEMBER") || $0.contains("[FORGET") }
                signals.append(contentsOf: memoryLines)
            }

            // Preserve user-stated facts and decisions (short user messages are often important)
            if role == "user" && content.count < 200 {
                signals.append("User said: \(content)")
            }

            // Preserve tool call results (summarized)
            if role == "assistant" && content.contains("tool_use") {
                // Just note which tools were called
                let toolMentions = content.components(separatedBy: "\n")
                    .filter { $0.contains("tool_use") || $0.contains("tool_call") }
                    .prefix(3)
                signals.append(contentsOf: toolMentions)
            }
        }

        // Build a compact summary as a system-role message
        if !signals.isEmpty {
            let summaryContent = "[Earlier conversation context — \(messagesToCompress.count) messages compressed]\n"
                + signals.prefix(20).joined(separator: "\n")
            conversationHistory = [["role": "user", "content": summaryContent]] + messagesToKeep
        } else {
            conversationHistory = messagesToKeep
        }

        let newTokens = conversationHistory.reduce(0) { total, msg in
            let content = msg["content"] as? String ?? ""
            return total + max(content.count / 4, 50)
        }

        NSLog("[LLM] Context compacted: %d → %d messages (~%d → ~%d tokens, %d signals preserved)",
              originalCount, conversationHistory.count, estimatedTokens, newTokens, signals.count)
    }

    // MARK: - LLM-Based Compression

    /// Compress the context window using an LLM to summarize old messages.
    /// Falls back to the heuristic compressor on failure.
    private func compressContextWindowWithLLM() async {
        let estimatedTokens = conversationHistory.reduce(0) { total, msg in
            let content: String
            if let text = msg["content"] as? String {
                content = text
            } else if let parts = msg["content"] as? [[String: Any]] {
                content = parts.compactMap { $0["text"] as? String }.joined()
            } else {
                content = ""
            }
            return total + max(content.count / 4, 50)
        }

        guard estimatedTokens > maxEstimatedTokens, conversationHistory.count > 6 else { return }

        // Select messages to compress vs keep
        let keepCount = max(6, conversationHistory.count / 3)
        let messagesToCompress = Array(conversationHistory.prefix(conversationHistory.count - keepCount))
        let messagesToKeep = Array(conversationHistory.suffix(keepCount))

        // Try LLM summarization
        if let summary = await summarizeMessages(messagesToCompress) {
            let originalCount = conversationHistory.count
            let summaryMessage: [String: Any] = [
                "role": "user",
                "content": "[Conversation summary — \(messagesToCompress.count) earlier messages]\n\(summary)"
            ]
            conversationHistory = [summaryMessage] + messagesToKeep

            let newTokens = conversationHistory.reduce(0) { total, msg in
                let content = msg["content"] as? String ?? ""
                return total + max(content.count / 4, 50)
            }
            NSLog("[LLM] LLM-compressed: %d → %d messages (~%d → ~%d tokens)",
                  originalCount, conversationHistory.count, estimatedTokens, newTokens)

            // Persist the summary to the active conversation thread
            if let store = conversationStore, let threadId = store.activeThreadId {
                await MainActor.run { store.updateCompressedSummary(summary, for: threadId) }
            }
            return
        }

        // Fallback to heuristic compression
        NSLog("[LLM] LLM summarization failed, falling back to heuristic compression")
        compressContextWindowIfNeeded()
    }

    /// Make a standalone LLM call to summarize a set of messages.
    /// Uses no tools and a small max_tokens budget. Returns nil on failure.
    private func summarizeMessages(_ messages: [[String: Any]]) async -> String? {
        guard let modelConfig = Config.activeModel else { return nil }

        // Build a text representation of the messages
        var transcript = ""
        for msg in messages {
            let role = msg["role"] as? String ?? "unknown"
            let content: String
            if let text = msg["content"] as? String {
                content = text
            } else if let parts = msg["content"] as? [[String: Any]] {
                content = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
            } else {
                continue
            }
            // Truncate very long messages to avoid blowing up the summarization call
            let truncated = content.count > 500 ? String(content.prefix(500)) + "…" : content
            transcript += "\(role): \(truncated)\n"
        }

        guard !transcript.isEmpty else { return nil }

        let summarizationPrompt = """
        Summarize the following conversation excerpt concisely. Preserve:
        - All user-stated facts, names, and preferences
        - Decisions made and commitments given
        - Tool calls and their key results
        - Memory commands ([REMEMBER], [FORGET])
        - Any unresolved questions or action items

        Keep it under 300 words. Use plain text, no formatting.

        CONVERSATION:
        \(transcript)
        """

        let provider = modelConfig.llmProvider

        do {
            // Use a lightweight request — no tools, short max_tokens
            switch provider {
            case .anthropic:
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(modelConfig.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.timeoutInterval = 15
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": 512,
                    "system": "You are a conversation summarizer. Be concise and factual.",
                    "messages": [["role": "user", "content": summarizationPrompt]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? [[String: Any]],
                      let text = content.first?["text"] as? String else { return nil }
                return text

            case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
                var baseURL = modelConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !baseURL.hasSuffix("/chat/completions") {
                    baseURL += baseURL.hasSuffix("/") ? "chat/completions" : "/chat/completions"
                }
                guard let url = URL(string: baseURL) else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(modelConfig.apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 15
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": 512,
                    "messages": [
                        ["role": "system", "content": "You are a conversation summarizer. Be concise and factual."],
                        ["role": "user", "content": summarizationPrompt]
                    ]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let text = message["content"] as? String else { return nil }
                return text

            case .gemini:
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelConfig.model):generateContent?key=\(modelConfig.apiKey)") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15
                let body: [String: Any] = [
                    "system_instruction": ["parts": [["text": "You are a conversation summarizer. Be concise and factual."]]],
                    "contents": [["role": "user", "parts": [["text": summarizationPrompt]]]],
                    "generationConfig": ["maxOutputTokens": 512]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else { return nil }
                return text

            case .local, .appleOnDevice:
                // Not worth running summarization on local models — use heuristic
                return nil
            }
        } catch {
            NSLog("[LLM] Summarization request failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Stateless one-shot vision analysis: sends `systemPrompt` + `userText` + a JPEG frame to the
    /// active provider with no tools and a small token budget, and does NOT mutate conversation
    /// history. Used by the Assistive Modes (A3) ambient loop, which must not pollute the chat.
    /// Returns the raw model text, or nil on failure / unsupported provider (local, appleOnDevice).
    func analyzeFrame(systemPrompt: String, userText: String, imageData: Data, maxTokens: Int = 200) async -> String? {
        guard let modelConfig = Config.activeModel else { return nil }
        let base64 = LLMImagePreparer.prepared(imageData).base64EncodedString()
        let provider = modelConfig.llmProvider

        do {
            switch provider {
            case .anthropic:
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(modelConfig.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.timeoutInterval = 20
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": maxTokens,
                    "system": systemPrompt,
                    "messages": [["role": "user", "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                        ["type": "text", "text": userText]
                    ]]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? [[String: Any]],
                      let text = content.first?["text"] as? String else { return nil }
                return text

            case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
                var baseURL = modelConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !baseURL.hasSuffix("/chat/completions") {
                    baseURL += baseURL.hasSuffix("/") ? "chat/completions" : "/chat/completions"
                }
                guard let url = URL(string: baseURL) else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(modelConfig.apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 20
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": maxTokens,
                    "messages": [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": [
                            ["type": "text", "text": userText],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                        ]]
                    ]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let text = message["content"] as? String else { return nil }
                return text

            case .gemini:
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelConfig.model):generateContent?key=\(modelConfig.apiKey)") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 20
                let body: [String: Any] = [
                    "system_instruction": ["parts": [["text": systemPrompt]]],
                    "contents": [["role": "user", "parts": [
                        ["text": userText],
                        ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
                    ]]],
                    "generationConfig": ["maxOutputTokens": maxTokens]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let text = parts.first?["text"] as? String else { return nil }
                return text

            case .local, .appleOnDevice:
                return nil
            }
        } catch {
            NSLog("[LLM] analyzeFrame request failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Stateless one-shot STRUCTURED vision analysis (structured-vision plan, Phase 2): like
    /// `analyzeFrame`, but forces the active provider to return a JSON object matching `jsonSchema` —
    /// Anthropic forced `tool_choice`, OpenAI-compatible forced function, Gemini JSON response. The
    /// pure `StructuredVisionParser` extracts the object and also falls back to tolerant parsing of any
    /// returned text, so a model that answers with prose JSON still yields a result. Does NOT mutate
    /// conversation history. Returns the JSON object, or nil on failure / unsupported provider
    /// (local, appleOnDevice). The caller decodes/validates against its schema.
    func analyzeFrameStructured(systemPrompt: String, userText: String, imageData: Data,
                                jsonSchema: [String: Any], toolName: String = "assessment",
                                maxTokens: Int = 1024) async -> [String: Any]? {
        guard let modelConfig = Config.activeModel else { return nil }
        let base64 = LLMImagePreparer.prepared(imageData).base64EncodedString()
        let provider = modelConfig.llmProvider
        let toolDescription = "Return the structured assessment for the image."

        do {
            switch provider {
            case .anthropic:
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(modelConfig.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.timeoutInterval = 30
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": maxTokens,
                    "system": systemPrompt,
                    "tools": [["name": toolName, "description": toolDescription, "input_schema": jsonSchema]],
                    "tool_choice": ["type": "tool", "name": toolName],
                    "messages": [["role": "user", "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                        ["type": "text", "text": userText]
                    ]]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return StructuredVisionParser.anthropic(data, toolName: toolName)

            case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
                var baseURL = modelConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !baseURL.hasSuffix("/chat/completions") {
                    baseURL += baseURL.hasSuffix("/") ? "chat/completions" : "/chat/completions"
                }
                guard let url = URL(string: baseURL) else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(modelConfig.apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 30
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": maxTokens,
                    "messages": [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": [
                            ["type": "text", "text": userText],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                        ]]
                    ],
                    "tools": [["type": "function", "function": [
                        "name": toolName, "description": toolDescription, "parameters": jsonSchema]]],
                    "tool_choice": ["type": "function", "function": ["name": toolName]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return StructuredVisionParser.openAI(data)

            case .gemini:
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelConfig.model):generateContent?key=\(modelConfig.apiKey)") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30
                // `responseMimeType` + a translated `responseSchema` enforce the exact JSON shape
                // (not just "some JSON") — the Gemini equivalent of Anthropic/OpenAI forced tool-use.
                let body: [String: Any] = [
                    "system_instruction": ["parts": [["text": systemPrompt]]],
                    "contents": [["role": "user", "parts": [
                        ["text": userText],
                        ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
                    ]]],
                    "generationConfig": [
                        "maxOutputTokens": maxTokens,
                        "responseMimeType": "application/json",
                        "responseSchema": GeminiSchemaTranslator.translate(jsonSchema)
                    ]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return StructuredVisionParser.gemini(data)

            case .local, .appleOnDevice:
                // On-device structured vision isn't supported here; the caller may fall back.
                return nil
            }
        } catch {
            NSLog("[LLM] analyzeFrameStructured request failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Stateless TEXT → JSON structured completion (no image, no conversation history) — the text sibling
    /// of `analyzeFrameStructured`. Cloud providers use forced tool-use / JSON mode; the on-device
    /// providers (Apple Foundation Models / local MLX) are prompted for JSON and parsed tolerantly, so
    /// the offline path works. Returns the JSON object, or nil on failure. Used by Study Mode generation.
    func completeStructured(systemPrompt: String, userText: String, jsonSchema: [String: Any],
                            toolName: String = "result", maxTokens: Int = 2048) async -> [String: Any]? {
        guard let modelConfig = Config.activeModel else { return nil }
        let provider = modelConfig.llmProvider
        let toolDescription = "Return the structured result."

        do {
            switch provider {
            case .anthropic:
                var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(modelConfig.apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.timeoutInterval = 45
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": maxTokens,
                    "system": systemPrompt,
                    "tools": [["name": toolName, "description": toolDescription, "input_schema": jsonSchema]],
                    "tool_choice": ["type": "tool", "name": toolName],
                    "messages": [["role": "user", "content": userText]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return StructuredVisionParser.anthropic(data, toolName: toolName)

            case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
                var baseURL = modelConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !baseURL.hasSuffix("/chat/completions") {
                    baseURL += baseURL.hasSuffix("/") ? "chat/completions" : "/chat/completions"
                }
                guard let url = URL(string: baseURL) else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(modelConfig.apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 45
                let body: [String: Any] = [
                    "model": modelConfig.model,
                    "max_tokens": maxTokens,
                    "messages": [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": userText]
                    ],
                    "tools": [["type": "function", "function": [
                        "name": toolName, "description": toolDescription, "parameters": jsonSchema]]],
                    "tool_choice": ["type": "function", "function": ["name": toolName]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return StructuredVisionParser.openAI(data)

            case .gemini:
                guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelConfig.model):generateContent?key=\(modelConfig.apiKey)") else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 45
                let body: [String: Any] = [
                    "system_instruction": ["parts": [["text": systemPrompt]]],
                    "contents": [["role": "user", "parts": [["text": userText]]]],
                    "generationConfig": [
                        "maxOutputTokens": maxTokens,
                        "responseMimeType": "application/json",
                        "responseSchema": GeminiSchemaTranslator.translate(jsonSchema)
                    ]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
                return StructuredVisionParser.gemini(data)

            case .appleOnDevice:
                let prompt = systemPrompt + "\n\nReturn ONLY a single valid JSON object matching the requested shape — no prose, no code fences."
                let text = try await sendAppleOnDevice(userText, systemPrompt: prompt)
                return AssessmentJSON.object(fromText: text)

            case .local:
                let prompt = systemPrompt + "\n\nReturn ONLY a single valid JSON object — no prose, no code fences."
                let text = try await sendLocal(userText, systemPrompt: prompt, config: modelConfig, includeTools: false)
                return AssessmentJSON.object(fromText: text)
            }
        } catch {
            NSLog("[LLM] completeStructured request failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Refresh the published model name from Config
    func refreshActiveModel() {
        activeModelName = Config.activeModel?.name ?? "No Model"
    }

    // MARK: - Anthropic Claude

    /// Route a request to the appropriate cloud provider for a given config.
    /// Used when a cloud model is selected as the agentic fast-tier model.
    private func sendCloud(_ text: String, systemPrompt: String, config: ModelConfig, includeTools: Bool) async throws -> String {
        switch config.llmProvider {
        case .anthropic:
            return try await sendAnthropic(text, systemPrompt: systemPrompt, config: config, includeTools: includeTools, imageData: nil)
        case .gemini:
            return try await sendGemini(text, systemPrompt: systemPrompt, config: config, includeTools: includeTools, imageData: nil)
        case .local, .appleOnDevice:
            throw LLMError.missingAPIKey("Local providers cannot be used as cloud agent")
        case .openai, .groq, .zai, .qwen, .minimax, .openrouter, .custom:
            return try await sendOpenAICompatible(text, systemPrompt: systemPrompt, config: config, includeTools: includeTools, imageData: nil)
        }
    }

    /// Capture the token usage block from a provider's response JSON and hand it to
    /// the cost tracker (Plan AU). Parsing is pure/synchronous here; only the resulting
    /// integer counts cross to the main actor (the non-Sendable JSON does not). A
    /// missing usage block is a silent no-op — never throws, never blocks the reply.
    /// Streaming turns (Chat tab `onToken`) don't carry a usage block on this path and
    /// are not yet captured.
    private func recordUsage(provider: LLMProvider, model: String, json: [String: Any]) {
        guard let tokens = UsageTracker.parseTokens(provider: provider, json: json) else { return }
        recordUsage(provider: provider, model: model, tokensIn: tokens.tokensIn, tokensOut: tokens.tokensOut)
    }

    /// Record already-parsed token counts (the streaming paths accumulate their own).
    private func recordUsage(provider: LLMProvider, model: String, tokensIn: Int, tokensOut: Int) {
        guard tokensIn + tokensOut > 0 else { return }
        Task { @MainActor in
            UsageTracker.shared.record(provider: provider, model: model, tokensIn: tokensIn, tokensOut: tokensOut)
        }
    }

    private func sendAnthropic(_ text: String, systemPrompt: String, config: ModelConfig, includeTools: Bool, imageData: Data?, onToken: ((String) -> Void)? = nil) async throws -> String {
        let apiKey = config.apiKey
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey("Anthropic API key not configured")
        }

        // Add user message to history
        if let imageData = imageData {
            let base64String = LLMImagePreparer.prepared(imageData).base64EncodedString()
            let content: [[String: Any]] = [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64String
                    ]
                ],
                [
                    "type": "text",
                    "text": text
                ]
            ]
            conversationHistory.append(["role": "user", "content": content])
        } else {
            conversationHistory.append(["role": "user", "content": text])
        }
        trimHistory()

        for iteration in 0..<maxToolCallIterations {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            var body: [String: Any] = [
                "model": config.model,
                "max_tokens": includeTools ? 1024 : Config.maxTokens,
                "system": systemPrompt,
                "messages": conversationHistory
            ]

            if includeTools {
                let includeOpenClaw = Config.isOpenClawConfigured && openClawBridge != nil
                let toolsData: Data = await MainActor.run {
                    let tools = ToolDeclarations.anthropicTools(registry: nativeToolRouter?.registry, includeOpenClaw: includeOpenClaw, mcpClient: nativeToolRouter?.mcpClient)
                    return (try? JSONSerialization.data(withJSONObject: tools)) ?? Data()
                }
                let tools = (try? JSONSerialization.jsonObject(with: toolsData)) as? [[String: Any]] ?? []
                body["tools"] = tools
            }

            if onToken != nil { body["stream"] = true }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            // Final-reply turns stream into the Chat tab when a streaming caller passes `onToken`;
            // the reconstructed content blocks + stop reason feed the existing tool loop unchanged.
            let content: [[String: Any]]
            let stopReason: String?
            if let onToken {
                (content, stopReason) = try await streamAnthropicContent(request: request, model: config.model, onToken: onToken)
            } else {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = (errorJson["error"] as? [String: Any])?["message"] as? String {
                        print("❌ Anthropic API error \(statusCode): \(errorMsg)")
                        throw LLMError.apiError(provider: "Anthropic", statusCode: statusCode, message: errorMsg)
                    }
                    throw LLMError.apiError(provider: "Anthropic", statusCode: statusCode, message: nil)
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let parsed = json["content"] as? [[String: Any]] else {
                    throw LLMError.invalidResponse("Anthropic")
                }
                content = parsed
                stopReason = json["stop_reason"] as? String
                recordUsage(provider: .anthropic, model: config.model, json: json)
            }

            // Check for tool use blocks
            if stopReason == "tool_use", includeTools {
                // Find tool_use blocks
                var toolUseBlocks: [[String: Any]] = []
                var textParts: [String] = []

                for block in content {
                    if let type = block["type"] as? String {
                        if type == "tool_use" {
                            toolUseBlocks.append(block)
                        } else if type == "text", let t = block["text"] as? String {
                            textParts.append(t)
                        }
                    }
                }

                // Add assistant message with tool_use to history
                conversationHistory.append(["role": "assistant", "content": content] as [String: Any])

                // Execute each tool call via NativeToolRouter
                for toolUse in toolUseBlocks {
                    guard let toolId = toolUse["id"] as? String,
                          let toolName = toolUse["name"] as? String,
                          let input = toolUse["input"] as? [String: Any] else { continue }

                    print("🔧 [Anthropic] Tool call: \(toolName)(\(String(describing: input).prefix(100))...)")
                    toolCallStatus = .executing(toolName)

                    let result: ToolResult
                    if let router = nativeToolRouter {
                        result = await router.handleToolCall(name: toolName, args: input)
                    } else if let bridge = openClawBridge {
                        let taskDesc = input["task"] as? String ?? String(describing: input)
                        result = await bridge.delegateTask(task: taskDesc, toolName: toolName)
                    } else {
                        result = .failure("No tool handler available")
                    }
                    toolCallStatus = result.isSuccess ? .completed(toolName) : .failed(toolName, "Failed")

                    let resultContent: String
                    switch result {
                    case .success(let text): resultContent = text
                    case .failure(let error): resultContent = "Error: \(error)"
                    }
                    // Frame untrusted external content as data, not instructions.
                    let framedContent = wrapToolResultForModel(toolName: toolName, content: resultContent)

                    conversationHistory.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": toolId,
                                "content": framedContent
                            ]
                        ]
                    ] as [String: Any])

                    // Yield-to-human: break out of the tool loop so the user can act
                    if toolName == "yield_to_human", case .success(let yieldText) = result,
                       yieldText.hasPrefix("YIELD_TO_HUMAN:") {
                        let reason = yieldText
                            .replacingOccurrences(of: "YIELD_TO_HUMAN: ", with: "")
                            .replacingOccurrences(of: "\nWaiting for you to say \"done\" or \"continue\" when ready.", with: "")
                        toolCallStatus = .yielded(toolName)
                        NSLog("[LLMService] Yielding to human: %@", reason)
                        return reason
                    }
                }

                print("🔄 [Anthropic] Continuing after tool call (iteration \(iteration + 1))")
                continue // Loop back to get final response
            }

            // No tool calls — extract text response
            let responseText = content.compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text",
                      let text = block["text"] as? String else { return nil }
                return text
            }.joined(separator: "\n")

            guard !responseText.isEmpty else {
                throw LLMError.invalidResponse("Anthropic")
            }

            conversationHistory.append(["role": "assistant", "content": responseText])
            toolCallStatus = .idle
            return responseText
        }

        // Exhausted iterations
        toolCallStatus = .idle
        throw LLMError.invalidResponse("Anthropic (tool call loop exceeded)")
    }

    // MARK: - OpenAI-compatible

    private func sendOpenAICompatible(_ text: String, systemPrompt: String, config: ModelConfig, includeTools: Bool, imageData: Data?, onToken: ((String) -> Void)? = nil) async throws -> String {
        let provider = config.llmProvider
        let apiKey = config.apiKey
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey("\(provider.displayName) API key not configured")
        }

        var baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseURL.hasSuffix("/chat/completions") {
            if baseURL.hasSuffix("/") {
                baseURL += "chat/completions"
            } else {
                baseURL += "/chat/completions"
            }
        }
        
        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidConfiguration("Invalid base URL: \(baseURL)")
        }

        // Add user message to history
        // Ensure we only attach images for models that are configured to accept them.
        // OpenAI-compatible endpoints vary a lot, so this is driven by the saved model config
        // with a heuristic fallback in `ModelConfig.visionEnabled`.
        let supportsVision = config.visionEnabled
        
        if let imageData = imageData, supportsVision {
            let base64String = LLMImagePreparer.prepared(imageData).base64EncodedString()
            // Custom providers proxying to Anthropic API need type:image with base64 source,
            // not OpenAI's type:image_url format.
            let isAnthropicProxy = provider == .custom && config.model.lowercased().contains("claude")
            let imageBlock: [String: Any] = isAnthropicProxy
                ? [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64String
                    ]
                ]
                : [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64String)"
                    ]
                ]
            let content: [[String: Any]] = [
                ["type": "text", "text": text],
                imageBlock
            ]
            conversationHistory.append(["role": "user", "content": content])
        } else if imageData != nil && !supportsVision {
            print("🖼️ Skipping image for model \(config.model) — vision disabled for this model configuration")
            // Drop the image but keep the text, and inform the model
            conversationHistory.append(["role": "user", "content": text + "\n[System note: The user attempted to send an image, but the current model (\(config.model)) does not support image analysis.]"])
        } else {
            conversationHistory.append(["role": "user", "content": text])
        }
        trimHistory()

        for iteration in 0..<maxToolCallIterations {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            // OpenRouter requires additional headers for tracking
            if provider == .openrouter {
                request.setValue("https://github.com/straff2002/OpenGlasses", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("OpenGlasses", forHTTPHeaderField: "X-Title")
            }

            // OpenAI format: system prompt is a message in the array.
            // Groq's free tier has tight TPM limits — trim history aggressively.
            let historySlice = provider == .groq ? Array(conversationHistory.suffix(6)) : conversationHistory
            var messages: [[String: Any]] = [
                ["role": "system", "content": systemPrompt]
            ]
            messages.append(contentsOf: historySlice)

            var body: [String: Any] = [
                "model": config.model,
                "max_tokens": includeTools ? 1024 : Config.maxTokens,
                "messages": messages
            ]

            // Only attach Tools if the provider reliably supports function calling.
            // Custom endpoints (Ollama/LMStudio) often crash with 400 if `tools` array is in the payload.
            let providerSupportsTools = provider == .openai || provider == .groq || provider == .zai || provider == .qwen || provider == .openrouter

            if includeTools && providerSupportsTools {
                let includeOpenClaw = Config.isOpenClawConfigured && openClawBridge != nil
                let toolsData: Data = await MainActor.run {
                    let tools = ToolDeclarations.openAITools(registry: nativeToolRouter?.registry, includeOpenClaw: includeOpenClaw, mcpClient: nativeToolRouter?.mcpClient)
                    return (try? JSONSerialization.data(withJSONObject: tools)) ?? Data()
                }
                let tools = (try? JSONSerialization.jsonObject(with: toolsData)) as? [[String: Any]] ?? []
                body["tools"] = tools
            }

            if onToken != nil {
                body["stream"] = true
                // Ask for a final usage chunk so the streamed path can record cost (Plan AU).
                // Servers that don't support it ignore the field; we then simply record nothing.
                body["stream_options"] = ["include_usage": true]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 60 // 60s timeout to prevent app freezing

            // Debug: log request details (redact base64 images)
            let messageCount = (body["messages"] as? [[String: Any]])?.count ?? 0
            let hasImage = imageData != nil && supportsVision
            let bodySize = request.httpBody?.count ?? 0
            print("🌐 \(provider.displayName) request: model=\(config.model) url=\(baseURL) messages=\(messageCount) hasImage=\(hasImage) bodySize=\(bodySize)")

            // Final-reply turns stream into the Chat tab when a streaming caller passes `onToken`;
            // the reconstructed `message` (content + tool_calls) feeds the existing tool loop unchanged.
            let message: [String: Any]
            if let onToken {
                message = try await streamOpenAIMessage(request: request, provider: provider, model: config.model, onToken: onToken)
            } else {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let rawBody = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                    print("❌ \(provider.displayName) raw error response (\(statusCode)): \(rawBody.prefix(500))")
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = errorJson["error"] as? [String: Any],
                       let errorMsg = errorObj["message"] as? String {
                        print("❌ \(provider.displayName) API error \(statusCode): \(errorMsg)")
                        throw LLMError.apiError(provider: provider.displayName, statusCode: statusCode, message: errorMsg)
                    }
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = errorJson["error"] as? String {
                        print("❌ \(provider.displayName) error \(statusCode): \(errorMsg)")
                        throw LLMError.apiError(provider: provider.displayName, statusCode: statusCode, message: errorMsg)
                    }
                    throw LLMError.apiError(provider: provider.displayName, statusCode: statusCode, message: nil)
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let m = choices.first?["message"] as? [String: Any] else {
                    throw LLMError.invalidResponse(provider.displayName)
                }
                message = m
                recordUsage(provider: provider, model: config.model, json: json)
            }

            // Check for tool calls
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty, includeTools {
                // Add assistant message with tool_calls to history
                conversationHistory.append(message)

                for toolCall in toolCalls {
                    guard let callId = toolCall["id"] as? String,
                          let function = toolCall["function"] as? [String: Any],
                          let functionName = function["name"] as? String,
                          let argsString = function["arguments"] as? String else { continue }

                    let args = (try? JSONSerialization.jsonObject(with: Data(argsString.utf8)) as? [String: Any]) ?? [:]

                    print("🔧 [OpenAI] Tool call: \(functionName)(\(String(describing: args).prefix(100))...)")
                    toolCallStatus = .executing(functionName)

                    let result: ToolResult
                    if let router = nativeToolRouter {
                        result = await router.handleToolCall(name: functionName, args: args)
                    } else if let bridge = openClawBridge {
                        let taskDesc = args["task"] as? String ?? argsString
                        result = await bridge.delegateTask(task: taskDesc, toolName: functionName)
                    } else {
                        result = .failure("No tool handler available")
                    }
                    toolCallStatus = result.isSuccess ? .completed(functionName) : .failed(functionName, "Failed")

                    let resultContent: String
                    switch result {
                    case .success(let text): resultContent = text
                    case .failure(let error): resultContent = "Error: \(error)"
                    }
                    // Frame untrusted external content as data, not instructions.
                    let framedContent = wrapToolResultForModel(toolName: functionName, content: resultContent)

                    conversationHistory.append([
                        "role": "tool",
                        "tool_call_id": callId,
                        "content": framedContent
                    ])

                    // Yield-to-human: break out of the tool loop so the user can act
                    if functionName == "yield_to_human", case .success(let yieldText) = result,
                       yieldText.hasPrefix("YIELD_TO_HUMAN:") {
                        let reason = yieldText
                            .replacingOccurrences(of: "YIELD_TO_HUMAN: ", with: "")
                            .replacingOccurrences(of: "\nWaiting for you to say \"done\" or \"continue\" when ready.", with: "")
                        toolCallStatus = .yielded(functionName)
                        NSLog("[LLMService] Yielding to human: %@", reason)
                        return reason
                    }
                }

                print("🔄 [OpenAI] Continuing after tool call (iteration \(iteration + 1))")
                continue // Loop back to get final response
            }

            // No tool calls — extract text response
            guard let responseText = message["content"] as? String else {
                throw LLMError.invalidResponse(provider.displayName)
            }

            conversationHistory.append(["role": "assistant", "content": responseText])
            toolCallStatus = .idle
            return responseText
        }

        // Exhausted iterations
        toolCallStatus = .idle
        throw LLMError.invalidResponse("\(provider.displayName) (tool call loop exceeded)")
    }

    // MARK: - Streaming (SSE) — Chat tab live token delivery

    /// Stream an OpenAI-compatible chat-completions response, invoking `onToken` for each text
    /// delta, and return a reconstructed `message` dict (same shape as `choices[].message`) so the
    /// caller's tool loop runs identically to the buffered path. Only used when a streaming caller
    /// (the Chat tab) passes `onToken`; every other caller keeps the buffered path.
    private func streamOpenAIMessage(request: URLRequest, provider: LLMProvider, model: String, onToken: @escaping (String) -> Void) async throws -> [String: Any] {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse(provider.displayName) }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            print("❌ \(provider.displayName) stream error \(http.statusCode): \(raw.prefix(300))")
            throw LLMError.apiError(provider: provider.displayName, statusCode: http.statusCode, message: msg)
        }

        var fullContent = ""
        var toolAcc: [Int: (id: String, name: String, args: String)] = [:]  // tool_calls accumulate by index
        var usage = StreamingUsageAccumulator()   // from the final include_usage chunk

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            usage.consumeOpenAI(obj)   // the usage chunk has empty choices, so parse it before the guard
            guard let choice = (obj["choices"] as? [[String: Any]])?.first,
                  let delta = choice["delta"] as? [String: Any] else { continue }

            if let chunk = delta["content"] as? String, !chunk.isEmpty {
                fullContent += chunk
                onToken(chunk)
            }
            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let idx = call["index"] as? Int ?? 0
                    var entry = toolAcc[idx] ?? (id: "", name: "", args: "")
                    if let id = call["id"] as? String { entry.id = id }
                    if let fn = call["function"] as? [String: Any] {
                        if let n = fn["name"] as? String { entry.name = n }
                        if let a = fn["arguments"] as? String { entry.args += a }
                    }
                    toolAcc[idx] = entry
                }
            }
        }

        recordUsage(provider: provider, model: model, tokensIn: usage.tokensIn, tokensOut: usage.tokensOut)

        var message: [String: Any] = ["role": "assistant", "content": fullContent]
        if !toolAcc.isEmpty {
            message["tool_calls"] = toolAcc.sorted { $0.key < $1.key }.map { _, v in
                ["id": v.id, "type": "function", "function": ["name": v.name, "arguments": v.args]] as [String: Any]
            }
        }
        return message
    }

    /// Stream an Anthropic Messages response, invoking `onToken` for each text delta, and return
    /// the reconstructed content blocks + stop reason so the caller's tool loop runs identically to
    /// the buffered path. Only used when a streaming caller (the Chat tab) passes `onToken`.
    private func streamAnthropicContent(request: URLRequest, model: String, onToken: @escaping (String) -> Void) async throws -> (content: [[String: Any]], stopReason: String?) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse("Anthropic") }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw LLMError.apiError(provider: "Anthropic", statusCode: http.statusCode, message: msg)
        }

        var blocks: [Int: [String: Any]] = [:]   // content blocks by index
        var toolJSON: [Int: String] = [:]         // accumulated input_json per tool_use block
        var stopReason: String?
        var usage = StreamingUsageAccumulator()   // input from message_start, output from message_delta

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            usage.consumeAnthropic(obj)

            switch type {
            case "content_block_start":
                let idx = obj["index"] as? Int ?? 0
                if let cb = obj["content_block"] as? [String: Any] {
                    blocks[idx] = cb
                    if (cb["type"] as? String) == "tool_use" { toolJSON[idx] = "" }
                }
            case "content_block_delta":
                let idx = obj["index"] as? Int ?? 0
                if let delta = obj["delta"] as? [String: Any], let dtype = delta["type"] as? String {
                    if dtype == "text_delta", let t = delta["text"] as? String {
                        var b = blocks[idx] ?? ["type": "text", "text": ""]
                        b["text"] = ((b["text"] as? String) ?? "") + t
                        blocks[idx] = b
                        onToken(t)
                    } else if dtype == "input_json_delta", let pj = delta["partial_json"] as? String {
                        toolJSON[idx, default: ""] += pj
                    }
                }
            case "message_delta":
                if let delta = obj["delta"] as? [String: Any], let sr = delta["stop_reason"] as? String {
                    stopReason = sr
                }
            default:
                break
            }
        }

        // Finalize tool_use blocks: parse the accumulated partial JSON into `input`.
        for (idx, jsonStr) in toolJSON {
            guard var b = blocks[idx] else { continue }
            b["input"] = (try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any]) ?? [:]
            blocks[idx] = b
        }

        recordUsage(provider: .anthropic, model: model, tokensIn: usage.tokensIn, tokensOut: usage.tokensOut)

        let content = blocks.sorted { $0.key < $1.key }.map { $0.value }
        return (content, stopReason)
    }

    // MARK: - Google Gemini

    private func sendGemini(_ text: String, systemPrompt: String, config: ModelConfig, includeTools: Bool, imageData: Data?) async throws -> String {
        let apiKey = config.apiKey
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey("Gemini API key not configured")
        }

        let model = config.model
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw LLMError.invalidConfiguration("Invalid Gemini URL")
        }

        // Add user message to history
        if let imageData = imageData {
            let base64String = LLMImagePreparer.prepared(imageData).base64EncodedString()
            let parts: [[String: Any]] = [
                ["text": text],
                ["inlineData": ["mimeType": "image/jpeg", "data": base64String]]
            ]
            conversationHistory.append(["role": "user", "parts": parts])
        } else {
            conversationHistory.append(["role": "user", "content": text])
        }
        trimHistory()

        for iteration in 0..<maxToolCallIterations {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Gemini format: system instruction + contents array
            var contents: [[String: Any]] = []
            for msg in conversationHistory {
                let role = msg["role"] as? String ?? "user"
                if role == "user" || role == "model" {
                    let geminiRole = role == "assistant" ? "model" : role
                    if let textContent = msg["content"] as? String {
                        contents.append([
                            "role": geminiRole,
                            "parts": [["text": textContent]]
                        ])
                    } else if let parts = msg["parts"] as? [[String: Any]] {
                        contents.append([
                            "role": geminiRole,
                            "parts": parts
                        ])
                    }
                } else if role == "assistant" {
                    if let textContent = msg["content"] as? String {
                        contents.append([
                            "role": "model",
                            "parts": [["text": textContent]]
                        ])
                    } else if let parts = msg["parts"] as? [[String: Any]] {
                        contents.append([
                            "role": "model",
                            "parts": parts
                        ])
                    }
                } else if role == "function" {
                    // Function response
                    if let parts = msg["parts"] as? [[String: Any]] {
                        contents.append([
                            "role": "user",
                            "parts": parts
                        ])
                    }
                }
            }

            var body: [String: Any] = [
                "system_instruction": [
                    "parts": [["text": systemPrompt]]
                ],
                "contents": contents,
                "generationConfig": [
                    "maxOutputTokens": includeTools ? 1024 : Config.maxTokens
                ]
            ]

            if includeTools {
                let includeOpenClaw = Config.isOpenClawConfigured && openClawBridge != nil
                let toolsData: Data = await MainActor.run {
                    let tools = ToolDeclarations.geminiRESTTools(registry: nativeToolRouter?.registry, includeOpenClaw: includeOpenClaw, mcpClient: nativeToolRouter?.mcpClient)
                    return (try? JSONSerialization.data(withJSONObject: tools)) ?? Data()
                }
                let tools = (try? JSONSerialization.jsonObject(with: toolsData)) as? [[String: Any]] ?? []
                body["tools"] = tools
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = errorJson["error"] as? [String: Any],
                   let errorMsg = errorObj["message"] as? String {
                    print("❌ Gemini API error \(statusCode): \(errorMsg)")
                    throw LLMError.apiError(provider: "Gemini", statusCode: statusCode, message: errorMsg)
                }
                throw LLMError.apiError(provider: "Gemini", statusCode: statusCode, message: nil)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw LLMError.invalidResponse("Gemini")
            }
            recordUsage(provider: .gemini, model: config.model, json: json)

            // Check for function calls in parts
            let functionCallParts = parts.filter { $0["functionCall"] != nil }

            if !functionCallParts.isEmpty, includeTools {
                // Add model response with function call to history
                conversationHistory.append([
                    "role": "assistant",
                    "parts": parts
                ])

                var functionResponseParts: [[String: Any]] = []

                for part in functionCallParts {
                    guard let funcCall = part["functionCall"] as? [String: Any],
                          let name = funcCall["name"] as? String,
                          let args = funcCall["args"] as? [String: Any] else { continue }

                    print("🔧 [Gemini] Tool call: \(name)(\(String(describing: args).prefix(100))...)")
                    toolCallStatus = .executing(name)

                    let result: ToolResult
                    if let router = nativeToolRouter {
                        result = await router.handleToolCall(name: name, args: args)
                    } else if let bridge = openClawBridge {
                        let taskDesc = args["task"] as? String ?? String(describing: args)
                        result = await bridge.delegateTask(task: taskDesc, toolName: name)
                    } else {
                        result = .failure("No tool handler available")
                    }
                    toolCallStatus = result.isSuccess ? .completed(name) : .failed(name, "Failed")

                    // Frame untrusted external content as data, not instructions.
                    let resultContent: [String: Any]
                    switch result {
                    case .success(let text):
                        resultContent = ["result": wrapToolResultForModel(toolName: name, content: text)]
                    case .failure(let error):
                        resultContent = ["error": error]
                    }

                    functionResponseParts.append([
                        "functionResponse": [
                            "name": name,
                            "response": resultContent
                        ]
                    ])
                }

                // Add function responses as user role
                conversationHistory.append([
                    "role": "function",
                    "parts": functionResponseParts
                ])

                // Yield-to-human: break out of the tool loop so the user can act
                if functionCallParts.contains(where: {
                    ($0["functionCall"] as? [String: Any])?["name"] as? String == "yield_to_human"
                }) {
                    if let yieldResponse = functionResponseParts.first(where: {
                        ($0["functionResponse"] as? [String: Any])?["name"] as? String == "yield_to_human"
                    }),
                       let response = (yieldResponse["functionResponse"] as? [String: Any])?["response"] as? [String: Any],
                       let yieldText = response["result"] as? String,
                       yieldText.hasPrefix("YIELD_TO_HUMAN:") {
                        let reason = yieldText
                            .replacingOccurrences(of: "YIELD_TO_HUMAN: ", with: "")
                            .replacingOccurrences(of: "\nWaiting for you to say \"done\" or \"continue\" when ready.", with: "")
                        toolCallStatus = .yielded("yield_to_human")
                        NSLog("[LLMService] Yielding to human: %@", reason)
                        return reason
                    }
                }

                print("🔄 [Gemini] Continuing after tool call (iteration \(iteration + 1))")
                continue // Loop back to get final response
            }

            // No function calls — extract text response
            let responseText = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")

            guard !responseText.isEmpty else {
                throw LLMError.invalidResponse("Gemini")
            }

            conversationHistory.append(["role": "assistant", "content": responseText])
            toolCallStatus = .idle
            return responseText
        }

        // Exhausted iterations
        toolCallStatus = .idle
        throw LLMError.invalidResponse("Gemini (tool call loop exceeded)")
    }

    // MARK: - Local (On-Device MLX)

    // MARK: - Apple Foundation Models (On-Device)

    private func sendAppleOnDevice(_ text: String, systemPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw LLMError.missingAPIKey("Apple Intelligence requires iOS 26+")
        }
        return try await sendAppleOnDeviceImpl(text, systemPrompt: systemPrompt)
        #else
        throw LLMError.missingAPIKey("Apple Foundation Models requires iOS 26+")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func sendAppleOnDeviceImpl(_ text: String, systemPrompt: String) async throws -> String {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            switch availability {
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    throw LLMError.missingAPIKey("Device does not support Apple Intelligence")
                case .appleIntelligenceNotEnabled:
                    throw LLMError.missingAPIKey("Enable Apple Intelligence in Settings > Apple Intelligence & Siri")
                case .modelNotReady:
                    throw LLMError.missingAPIKey("Apple Intelligence model is still downloading, try again later")
                @unknown default:
                    throw LLMError.missingAPIKey("Apple Intelligence unavailable")
                }
            default:
                throw LLMError.missingAPIKey("Apple Intelligence unavailable")
            }
        }

        if appleSession == nil {
            appleSession = LanguageModelSession(instructions: systemPrompt)
        }

        let response = try await appleSession!.respond(to: text)
        return response.content
    }
    #endif

    private func sendLocal(_ text: String, systemPrompt: String, config: ModelConfig, includeTools: Bool, imageData: Data? = nil, onToken: ((String) -> Void)? = nil) async throws -> String {
        guard let localService = localLLMService else {
            throw LLMError.missingAPIKey("Local LLM service not initialized")
        }

        // Load the configured model (no auto-swap — user picks one model)
        if !localService.isModelLoaded || localService.loadedModelId != config.model {
            try await localService.loadModel(config.model)
        }

        // Build tool instructions — use minimal set for local models
        var fullPrompt = systemPrompt
        if includeTools, let router = nativeToolRouter {
            // Local models get a reduced tool set — only simple, reliable tools
            let localSafeTools: Set<String> = [
                "get_weather", "get_datetime", "calculate", "set_timer",
                "flashlight", "brightness", "calendar", "reminder",
                "set_alarm", "step_count", "device_info", "music_control"
            ]
            let toolNames = router.registry.toolNames.filter { localSafeTools.contains($0) }
            if !toolNames.isEmpty {
                fullPrompt += """

                \nTOOLS (use sparingly, only when the user clearly needs one):
                Output exactly: <tool_call>{"name": "tool_name", "arguments": {"key": "value"}}</tool_call>
                Available: \(toolNames.joined(separator: ", "))
                Only use a tool if the user explicitly asks for that action. Otherwise just answer directly.
                """
            }
        }

        // Build history — keep only last 2 exchanges for local models (context is precious)
        let recentHistory = conversationHistory.suffix(4)
        var history: [(role: String, content: String)] = []
        for turn in recentHistory {
            if let role = turn["role"] as? String, let content = turn["content"] as? String {
                // Strip any tool call markup from history to keep context clean
                let clean = content
                    .replacingOccurrences(of: #"<tool_call>.*?</tool_call>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    history.append((role: role, content: clean))
                }
            }
        }

        // Add user message to history
        conversationHistory.append(["role": "user", "content": text])
        trimHistory()

        // Generate response. Stream tokens to the UI as they're produced. In the (rare, the local
        // tool prompt says "use sparingly") case where the model emits a <tool_call>, the preview
        // briefly shows the markup before the cleaned final reply replaces it — acceptable for the
        // common no-tool path, which streams cleanly.
        let response: String
        do {
            response = try await localService.generate(
                userMessage: text,
                systemPrompt: fullPrompt,
                history: history,
                onToken: onToken
            )
        } catch let error as LocalLLMError {
            // Propagate .backgrounded unwrapped so callers (e.g. AgentScheduler) can
            // tell "can't run on-device in background" apart from a real failure and
            // defer rather than consuming the scheduled run.
            print("❌ Local model generation failed: \(error)")
            throw error
        } catch {
            print("❌ Local model generation failed: \(error)")
            throw LLMError.invalidResponse("Local model error: \(error.localizedDescription)")
        }

        // Try to parse tool calls — but don't crash if the model doesn't support them well
        let toolCallPattern = #"<tool_call>\s*(\{.*?\})\s*</tool_call>"#
        if let regex = try? NSRegularExpression(pattern: toolCallPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
           let jsonRange = Range(match.range(at: 1), in: response),
           let toolCallData = String(response[jsonRange]).data(using: .utf8),
           let toolCall = try? JSONSerialization.jsonObject(with: toolCallData) as? [String: Any],
           let toolName = toolCall["name"] as? String,
           let toolArgs = toolCall["arguments"] as? [String: Any],
           let router = nativeToolRouter {

            // Execute the tool
            print("🔧 Local model tool call: \(toolName)(\(toolArgs))")
            toolCallStatus = .executing(toolName)
            let result = await router.handleToolCall(name: toolName, args: toolArgs)
            toolCallStatus = .idle

            let resultText: String
            switch result {
            case .success(let text): resultText = text
            case .failure(let error): resultText = "Error: \(error)"
            }

            // Get the text before the tool call as context
            let textBefore = response
                .replacingOccurrences(of: #"<tool_call>.*?</tool_call>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Try to re-generate with tool result for a natural response
            var updatedHistory = history
            updatedHistory.append((role: "assistant", content: textBefore.isEmpty ? "Let me check that for you." : textBefore))
            updatedHistory.append((role: "user", content: "Tool '\(toolName)' returned: \(resultText). Please respond naturally to the user based on this result."))

            let finalResponse: String
            do {
                finalResponse = try await localService.generate(
                    userMessage: "Respond to the user based on the tool result above.",
                    systemPrompt: fullPrompt,
                    history: updatedHistory
                )
            } catch {
                // If re-generation fails, just return the tool result directly
                finalResponse = textBefore.isEmpty ? resultText : "\(textBefore) \(resultText)"
            }

            let cleanFinal = finalResponse
                .replacingOccurrences(of: #"<tool_call>.*?</tool_call>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            conversationHistory.append(["role": "assistant", "content": cleanFinal])
            trimHistory()
            return cleanFinal
        }

        // No tool call — clean up any partial tool markup and return
        let cleanResponse = response
            .replacingOccurrences(of: #"<tool_call>.*?</tool_call>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        conversationHistory.append(["role": "assistant", "content": cleanResponse])
        trimHistory()
        return cleanResponse
    }

    // MARK: - Local Agent Model

    /// Send a message through the on-device agent model (Gemma 4 via MLX).
    /// Used for fast-tier queries when agentic mode is enabled.
    /// Builds its own lightweight prompt and routes through sendLocal().
    func sendViaLocalAgent(_ text: String, locationContext: String? = nil, memoryContext: String? = nil) async throws -> String {
        let agentModelId = Config.agentModelId

        let hasNativeTools = nativeToolRouter != nil
        let nativeToolNames = nativeToolRouter?.registry.toolNames ?? []
        let fullPrompt = await Self.buildSystemPrompt(
            locationContext: locationContext,
            includeTools: hasNativeTools,
            includeOpenClaw: false,
            hasImage: false,
            nativeToolNames: nativeToolNames,
            memoryContext: memoryContext,
            turn: text
        )

        // If a cloud model config is selected as the agent, route through it
        if let cloudConfig = Config.savedModels.first(where: { $0.id == agentModelId }) {
            print("🧠 Cloud agent: \(cloudConfig.name)")
            return try await sendCloud(text, systemPrompt: fullPrompt, config: cloudConfig, includeTools: hasNativeTools)
        }

        // Otherwise use the local on-device model
        guard let localService = localLLMService else {
            throw LLMError.missingAPIKey("Local LLM service not initialized")
        }
        if !localService.isModelLoaded || localService.loadedModelId != agentModelId {
            try await localService.loadModel(agentModelId)
        }
        let localConfig = ModelConfig(
            id: "local-agent",
            name: "Local Agent",
            provider: LLMProvider.local.rawValue,
            apiKey: "",
            model: agentModelId,
            baseURL: ""
        )
        print("🧠 Local agent: \(agentModelId)")
        return try await sendLocal(text, systemPrompt: fullPrompt, config: localConfig, includeTools: hasNativeTools)
    }

    // MARK: - Helpers

    /// Trim history only when token budget is exceeded — no fixed turn limit.
    /// Preserves recent context and any messages containing memory commands or important decisions.
    private func trimHistory() {
        compressContextWindowIfNeeded()
    }

    /// Inject a hidden system message into conversation history.
    /// Used by the memory nudge to prompt periodic review without the user seeing it.
    func injectSystemMessage(_ message: String) {
        conversationHistory.append(["role": "user", "content": message])
    }
}

// MARK: - ToolResult Helper

extension ToolResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - Think Tag Stripping

extension LLMService {
    /// Strip `<think>...</think>` blocks from LLM output.
    /// Returns the spoken text (without think tags) and the extracted reasoning (if any).
    static func stripThinkTags(_ text: String) -> (spoken: String, reasoning: String?) {
        let pattern = "<think>[\\s\\S]*?</think>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, nil)
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return (text, nil) }

        // Extract all reasoning blocks
        let reasoning = matches.compactMap { match -> String? in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            var block = String(text[matchRange])
            block = block.replacingOccurrences(of: "<think>", with: "")
            block = block.replacingOccurrences(of: "</think>", with: "")
            return block.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n")

        // Remove think tags from the spoken output
        let spoken = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (spoken, reasoning.isEmpty ? nil : reasoning)
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case missingAPIKey(String)
    case invalidResponse(String)
    case invalidConfiguration(String)
    case apiError(provider: String, statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): return msg
        case .invalidResponse(let provider): return "Invalid response from \(provider)"
        case .invalidConfiguration(let msg): return msg
        case .apiError(let provider, let code, let msg):
            if let msg { return "\(provider) error \(code): \(msg)" }
            return "\(provider) error: \(code)"
        }
    }
}
