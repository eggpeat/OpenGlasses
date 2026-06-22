import XCTest
@testable import OpenGlasses

/// Headless tests for the siri-and-local-server follow-ups: the pure connection-result
/// classifier and the local-server presets. The network probe itself is a thin shell; its
/// result mapping (`classify`) is pure and tested here.
final class SiriLocalServerTests: XCTestCase {

    // MARK: - ConnectionTestResult.classify

    func testClassifyOK() {
        XCTAssertEqual(ModelFetcher.classify(statusCode: 200, modelCount: 5, latencyMs: 42),
                       .ok(latencyMs: 42, modelCount: 5))
        XCTAssertTrue(ModelFetcher.classify(statusCode: 204, modelCount: 0, latencyMs: 10).isSuccess)
    }

    func testClassifyReachableButNoModelsStillOK() {
        let r = ModelFetcher.classify(statusCode: 200, modelCount: 0, latencyMs: 7)
        XCTAssertEqual(r, .ok(latencyMs: 7, modelCount: 0))   // server up, just nothing loaded
    }

    func testClassifyHTTPErrors() {
        XCTAssertEqual(ModelFetcher.classify(statusCode: 401, modelCount: 0, latencyMs: 5), .httpError(401))
        XCTAssertEqual(ModelFetcher.classify(statusCode: 404, modelCount: 0, latencyMs: 5), .httpError(404))
        XCTAssertEqual(ModelFetcher.classify(statusCode: 503, modelCount: 0, latencyMs: 5), .httpError(503))
        XCTAssertFalse(ModelFetcher.classify(statusCode: 500, modelCount: 0, latencyMs: 5).isSuccess)
    }

    // MARK: - LocalServerPreset

    func testPresetsCoverTheCommonServers() {
        XCTAssertEqual(Set(LocalServerPreset.allCases.map(\.displayName)),
                       ["Ollama", "LM Studio", "vLLM", "LocalAI"])
    }

    func testPresetBaseURLsAreLocalAndDistinct() {
        let urls = LocalServerPreset.allCases.map(\.baseURL)
        XCTAssertEqual(Set(urls).count, urls.count)                       // all distinct
        XCTAssertTrue(urls.allSatisfy { $0.hasPrefix("http://localhost:") && $0.hasSuffix("/v1") })
        XCTAssertEqual(LocalServerPreset.ollama.baseURL, "http://localhost:11434/v1")
    }

    func testPresetModelHintsPresent() {
        XCTAssertTrue(LocalServerPreset.allCases.allSatisfy { !$0.modelHint.isEmpty })
    }

    func testPresetEndpointDerivationRoundTrips() {
        // A preset base URL → the /models listing endpoint the probe hits.
        XCTAssertEqual(ModelFetcher.modelsEndpoint(from: LocalServerPreset.ollama.baseURL),
                       "http://localhost:11434/v1/models")
    }
}
