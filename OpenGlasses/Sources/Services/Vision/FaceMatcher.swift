import Foundation

/// Pure face-embedding matching math for `FaceRecognitionService` — cosine similarity plus
/// best-match-above-threshold selection. Kept separate so the recognition decision is
/// headless-testable without a camera or the Vision framework.
enum FaceMatcher {

    /// Cosine similarity of two equal-length vectors (0 for mismatched/empty inputs).
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, magA: Float = 0, magB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let mag = sqrt(magA) * sqrt(magB)
        return mag > 0 ? dot / mag : 0
    }

    /// Index of the candidate with the highest cosine similarity to `faceprint` that also clears
    /// `threshold`, or nil if none qualify. Candidates whose length differs are skipped.
    static func bestMatch(for faceprint: [Float], among candidates: [[Float]], threshold: Float) -> Int? {
        var bestIndex: Int?
        var bestSimilarity = threshold   // must strictly exceed the threshold to match
        for (idx, candidate) in candidates.enumerated() {
            guard candidate.count == faceprint.count else { continue }
            let similarity = cosineSimilarity(faceprint, candidate)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestIndex = idx
            }
        }
        return bestIndex
    }
}
