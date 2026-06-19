import Foundation

/// PURE: grade a quiz attempt (docs/plans/study-mode.md). `answers` maps question id → chosen option id.
struct QuizGrader {
    func grade(_ quiz: [QuizQuestion], answers: [String: String]) -> QuizResult {
        guard !quiz.isEmpty else { return QuizResult(total: 0, correct: 0, percentage: 0, missed: []) }
        var correct = 0
        var missed: [QuizQuestion] = []
        for question in quiz {
            if answers[question.id] == question.correctOptionID {
                correct += 1
            } else {
                missed.append(question)
            }
        }
        let percentage = Double(correct) / Double(quiz.count) * 100
        return QuizResult(total: quiz.count, correct: correct, percentage: percentage, missed: missed)
    }
}
