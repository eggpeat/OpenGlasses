import Foundation

/// Builds the generation prompt + response schema for a study deck, and parses/validates the model's
/// `{ summary, flashcards[], quiz[] }` output into a `StudyDeck` (docs/plans/study-mode.md). The parse
/// is pure + headless (the LLM call lives in `StudyService`); reuses the tolerant `AssessmentJSON`.
enum StudyContentBuilder {

    enum StudyError: Error, LocalizedError {
        case noFlashcards
        case malformed(String)
        var errorDescription: String? {
            switch self {
            case .noFlashcards: return "The document didn't yield any usable flashcards."
            case .malformed(let m): return "Couldn't parse the study content: \(m)"
            }
        }
    }

    static func jsonSchema(maxFlashcards: Int = 12, maxQuiz: Int = 6) -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "summary": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "overview": ["type": "string"],
                        "key_points": ["type": "array", "items": ["type": "string"]],
                        "doc_type": ["type": "string"]
                    ],
                    "required": ["title", "overview"]
                ],
                "flashcards": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["front": ["type": "string"], "back": ["type": "string"]],
                        "required": ["front", "back"]
                    ]
                ],
                "quiz": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "prompt": ["type": "string"],
                            "options": ["type": "array", "items": ["type": "string"]],
                            "correct_index": ["type": "integer", "description": "0-based index of the correct option"]
                        ],
                        "required": ["prompt", "options", "correct_index"]
                    ]
                ]
            ],
            "required": ["summary", "flashcards", "quiz"]
        ]
    }

    static func systemPrompt(maxFlashcards: Int = 12, maxQuiz: Int = 6) -> String {
        """
        You are a study assistant. From the supplied document text, produce active-recall study material. \
        Return ONLY structured content with: a `summary` (title, 1–3 sentence overview, 3–5 key_points, \
        and doc_type), up to \(maxFlashcards) `flashcards` (each a front question/term and a back answer), \
        and up to \(maxQuiz) `quiz` multiple-choice questions (each with a prompt, 3–4 plausible options, \
        and correct_index = the 0-based index of the single correct option). Base every card and question \
        only on the document; make distractors plausible but clearly wrong. Keep fronts/backs concise.
        """
    }

    static func userText(forContent content: String) -> String {
        "Create study material from this document:\n\n\(content)"
    }

    // MARK: - Parse / validate

    private struct DTO: Decodable {
        let summary: SummaryDTO?
        let flashcards: [CardDTO]?
        let quiz: [QuizDTO]?
        struct SummaryDTO: Decodable {
            let title: String?; let overview: String?; let keyPoints: [String]?; let docType: String?
            enum CodingKeys: String, CodingKey { case title, overview; case keyPoints = "key_points"; case docType = "doc_type" }
        }
        struct CardDTO: Decodable { let front: String?; let back: String? }
        struct QuizDTO: Decodable {
            let prompt: String?; let options: [String]?; let correctIndex: Int?
            enum CodingKeys: String, CodingKey { case prompt, options; case correctIndex = "correct_index" }
        }
    }

    /// Parse + validate the model JSON into a deck. Requires ≥1 usable flashcard; invalid MCQs
    /// (fewer than 2 options or an out-of-range correct index) are dropped, not fatal.
    static func parse(_ json: [String: Any], id: String = UUID().uuidString,
                      createdAt: Date = Date(), source: String? = nil) throws -> StudyDeck {
        let dto: DTO
        do { dto = try AssessmentJSON.decode(DTO.self, from: json) }
        catch { throw StudyError.malformed("\(error)") }

        let flashcards: [Flashcard] = (dto.flashcards ?? []).compactMap { c in
            let front = c.front?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let back = c.back?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return Flashcard(front: front, back: back)
        }
        guard !flashcards.isEmpty else { throw StudyError.noFlashcards }

        let quiz: [QuizQuestion] = (dto.quiz ?? []).enumerated().compactMap { idx, q in
            let prompt = q.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let texts = (q.options ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !prompt.isEmpty, texts.count >= 2, let ci = q.correctIndex, texts.indices.contains(ci) else { return nil }
            let options = texts.enumerated().map { QuizOption(id: "q\(idx)o\($0.offset)", text: $0.element) }
            return QuizQuestion(id: "q\(idx)", prompt: prompt, options: options, correctOptionID: "q\(idx)o\(ci)")
        }

        let s = dto.summary
        let summary = StudySummary(
            title: s?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Study deck",
            overview: s?.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            keyPoints: (s?.keyPoints ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            docType: s?.docType?.nonEmpty)

        return StudyDeck(id: id, createdAt: createdAt, source: source,
                         summary: summary, flashcards: flashcards, quiz: quiz)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
