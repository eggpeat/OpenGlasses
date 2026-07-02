import XCTest
@testable import OpenGlasses

/// Tests for the pure face-embedding matching math extracted from `FaceRecognitionService`.
final class FaceMatcherTests: XCTestCase {

    func testCosineSimilarityIdenticalVectors() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(FaceMatcher.cosineSimilarity(v, v), 1.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOrthogonal() {
        XCTAssertEqual(FaceMatcher.cosineSimilarity([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarityMismatchedOrEmpty() {
        XCTAssertEqual(FaceMatcher.cosineSimilarity([1, 2, 3], [1, 2]), 0)
        XCTAssertEqual(FaceMatcher.cosineSimilarity([], []), 0)
        XCTAssertEqual(FaceMatcher.cosineSimilarity([0, 0], [0, 0]), 0, "zero-magnitude → 0, no NaN")
    }

    func testBestMatchPicksHighestAboveThreshold() {
        let probe: [Float] = [1, 0, 0]
        let candidates: [[Float]] = [
            [0.9, 0.1, 0],   // high similarity
            [0.5, 0.5, 0],   // lower
            [1, 0, 0],       // exact
        ]
        // Exact match (index 2) is the highest similarity.
        XCTAssertEqual(FaceMatcher.bestMatch(for: probe, among: candidates, threshold: 0.6), 2)
    }

    func testBestMatchReturnsNilWhenNoneClearThreshold() {
        let probe: [Float] = [1, 0, 0]
        let candidates: [[Float]] = [[0, 1, 0], [0, 0, 1]]   // orthogonal → similarity 0
        XCTAssertNil(FaceMatcher.bestMatch(for: probe, among: candidates, threshold: 0.6))
    }

    func testBestMatchSkipsLengthMismatches() {
        let probe: [Float] = [1, 0, 0]
        let candidates: [[Float]] = [[1, 0], [1, 0, 0]]   // first is wrong length → skipped
        XCTAssertEqual(FaceMatcher.bestMatch(for: probe, among: candidates, threshold: 0.6), 1)
    }

    func testBestMatchThresholdIsStrict() {
        let probe: [Float] = [1, 0]
        let candidates: [[Float]] = [[1, 0]]   // similarity exactly 1.0
        XCTAssertNil(FaceMatcher.bestMatch(for: probe, among: candidates, threshold: 1.0),
                     "a candidate must strictly exceed the threshold")
        XCTAssertEqual(FaceMatcher.bestMatch(for: probe, among: candidates, threshold: 0.99), 0)
    }

    func testBestMatchEmptyCandidates() {
        XCTAssertNil(FaceMatcher.bestMatch(for: [1, 0, 0], among: [], threshold: 0.6))
    }
}
