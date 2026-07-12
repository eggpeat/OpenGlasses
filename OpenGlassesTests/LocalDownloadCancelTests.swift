import XCTest
@testable import OpenGlasses

/// BK P5 — model-download "Cancel" was a UI-only no-op: `activeDownloadTask` was never assigned
/// (the real Task lived in the caller), so `cancelDownload()` cancelled a nil task while the
/// download ran to completion, and clearing `isDownloading` let a second multi-GB download start
/// over the same progress state. Driven through the injected `downloadFunction` seam (no network).
@MainActor
final class LocalDownloadCancelTests: XCTestCase {

    /// A long fake download that honours cancellation and reports progress.
    private func longDownload(_ progressing: XCTestExpectation) -> (String, @escaping (Double) -> Void) async throws -> Void {
        { _, onProgress in
            for i in 1...1_000_000 {
                try Task.checkCancellation()
                onProgress(min(1.0, Double(i) / 1_000_000))
                progressing.fulfill()
                await Task.yield()
            }
        }
    }

    func testCancelDownloadStopsTheInFlightDownload() async {
        let service = LocalLLMService()
        let progressing = expectation(description: "downloading"); progressing.assertForOverFulfill = false
        service.downloadFunction = longDownload(progressing)

        let download = Task { try await service.downloadModel("mlx-community/whatever") }
        await fulfillment(of: [progressing], timeout: 2.0)
        XCTAssertTrue(service.isDownloading, "the download is live")

        service.cancelDownload()
        do {
            try await download.value
            XCTFail("a cancelled download must throw, not complete")
        } catch is CancellationError {
            // correct — the in-flight download was actually stopped
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        XCTAssertFalse(service.isDownloading, "state resets after cancel")
        XCTAssertNil(service.downloadingModelId)
    }

    func testSecondDownloadWhileActiveIsRejectedWithVisibleError() async {
        let service = LocalLLMService()
        let progressing = expectation(description: "downloading"); progressing.assertForOverFulfill = false
        service.downloadFunction = longDownload(progressing)

        let first = Task { try? await service.downloadModel("mlx-community/model-a") }
        await fulfillment(of: [progressing], timeout: 2.0)
        XCTAssertTrue(service.isDownloading)

        do {
            try await service.downloadModel("mlx-community/model-b")
            XCTFail("a second concurrent download must be rejected")
        } catch let error as LocalLLMError {
            guard case .alreadyDownloading = error else {
                return XCTFail("expected .alreadyDownloading, got \(error)")
            }
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "the rejection must carry a visible message")
        } catch {
            XCTFail("expected .alreadyDownloading, got \(error)")
        }

        service.cancelDownload()
        _ = await first.value
    }

    func testSuccessfulDownloadReportsProgressAndCompletes() async throws {
        let service = LocalLLMService()
        var reached = false
        service.downloadFunction = { _, onProgress in
            onProgress(0.25)
            onProgress(0.75)
            reached = true
        }
        try await service.downloadModel("mlx-community/model-x")
        XCTAssertTrue(reached, "the download function ran to completion")
        XCTAssertEqual(service.downloadProgress, 1.0, "completes at 100%")
        XCTAssertFalse(service.isDownloading)
        XCTAssertNil(service.downloadingModelId)
    }
}
