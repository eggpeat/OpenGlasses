import XCTest
@testable import OpenGlasses

final class LocalServerDiscoveryTests: XCTestCase {

    func testRewriteHostPreservesSchemePortAndPath() {
        XCTAssertEqual(
            LocalServerDiscovery.rewriteHost("http://localhost:11434/v1", to: "mac.local"),
            "http://mac.local:11434/v1")
        XCTAssertEqual(
            LocalServerDiscovery.rewriteHost("http://localhost:1234/v1", to: "192.168.1.50"),
            "http://192.168.1.50:1234/v1")
    }

    func testRewriteHostNilOnGarbage() {
        XCTAssertNil(LocalServerDiscovery.rewriteHost("not a url", to: "host"))
        XCTAssertNil(LocalServerDiscovery.rewriteHost("", to: "host"))
    }

    func testCandidatesCoverEveryPresetPort() {
        let candidates = LocalServerDiscovery.candidates(host: "mac.local")
        let urls = Set(candidates.map(\.baseURL))
        XCTAssertTrue(urls.contains("http://mac.local:11434/v1"))  // Ollama
        XCTAssertTrue(urls.contains("http://mac.local:1234/v1"))   // LM Studio
        XCTAssertTrue(urls.contains("http://mac.local:8000/v1"))   // vLLM
        XCTAssertTrue(urls.contains("http://mac.local:8080/v1"))   // LocalAI
        // One candidate per distinct preset port.
        XCTAssertEqual(candidates.count, LocalServerPreset.allCases.count)
    }

    func testCandidatesEmptyForBlankHost() {
        XCTAssertTrue(LocalServerDiscovery.candidates(host: "   ").isEmpty)
        XCTAssertTrue(LocalServerDiscovery.candidates(host: "").isEmpty)
    }

    func testCandidatesDedupeIdenticalURLs() {
        // Two presets sharing a port would collapse to one candidate; with the
        // shipped presets all ports differ, so count equals preset count and URLs
        // are unique.
        let candidates = LocalServerDiscovery.candidates(host: "host.local")
        XCTAssertEqual(Set(candidates.map(\.baseURL)).count, candidates.count)
    }
}
