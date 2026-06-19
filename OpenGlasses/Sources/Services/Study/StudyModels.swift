import Foundation

// Study Mode models (docs/plans/study-mode.md). Pure, Codable, headless.

/// A single flashcard — a prompt (front) and its answer (back).
struct Flashcard: Codable, Identifiable, Equatable {
    let id: String
    let front: String
    let back: String

    init(id: String = UUID().uuidString, front: String, back: String) {
        self.id = id
        self.front = front
        self.back = back
    }
}

/// One option of a multiple-choice question.
struct QuizOption: Codable, Identifiable, Equatable {
    let id: String
    let text: String
}

/// A multiple-choice question — a prompt, ≥2 options, and exactly one correct option.
struct QuizQuestion: Codable, Identifiable, Equatable {
    let id: String
    let prompt: String
    let options: [QuizOption]
    let correctOptionID: String

    var correctOption: QuizOption? { options.first { $0.id == correctOptionID } }
}

/// Deck-level summary produced alongside the cards.
struct StudySummary: Codable, Equatable {
    let title: String
    let overview: String
    let keyPoints: [String]
    let docType: String?

    enum CodingKeys: String, CodingKey {
        case title, overview
        case keyPoints = "key_points"
        case docType = "doc_type"
    }
}

/// A study deck: a summary plus flashcards and a quiz, generated from a source document.
struct StudyDeck: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let source: String?          // source document name / id
    let summary: StudySummary
    let flashcards: [Flashcard]
    let quiz: [QuizQuestion]
}

/// Leitner review state for one flashcard.
struct ReviewRecord: Codable, Equatable {
    let cardID: String
    let box: Int                 // 0 = resurface soonest
    let dueAt: TimeInterval      // seconds since reference date
    let lastReviewed: TimeInterval
}

/// The outcome of grading a quiz attempt.
struct QuizResult: Equatable {
    let total: Int
    let correct: Int
    let percentage: Double
    let missed: [QuizQuestion]
}
