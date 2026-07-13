import XCTest
@testable import OpenGlasses

/// Admission rule for loading on-device models (MemoryHeadroom.canLoad).
///
/// The gate exists because an oversized load doesn't fail cleanly — it ends in a
/// silent Jetsam kill. The rule must refuse loads that can't fit weights + working
/// overhead, but must NOT refuse when either number is unknown (model not on disk
/// yet, or a platform with no per-app budget like the simulator), or it would brick
/// loading exactly where the guard isn't needed.
final class MemoryHeadroomTests: XCTestCase {

    private let gb: Int64 = 1_073_741_824

    func testLoadAllowedWithComfortableHeadroom() {
        XCTAssertTrue(MemoryHeadroom.canLoad(modelBytes: 3 * gb, availableBytes: 6 * gb))
    }

    func testLoadRefusedWhenWeightsAloneDontFit() {
        XCTAssertFalse(MemoryHeadroom.canLoad(modelBytes: 4 * gb, availableBytes: 3 * gb))
    }

    func testLoadRefusedWhenWeightsFitButOverheadDoesnt() {
        // Weights fit exactly, but generation-time overhead (KV cache, activations,
        // Metal buffers) would push past the budget — the 2026-07-13 crash pattern.
        XCTAssertFalse(MemoryHeadroom.canLoad(modelBytes: 3 * gb, availableBytes: 3 * gb))
    }

    func testBoundaryExactFitIsAllowed() {
        let model = 3 * gb
        XCTAssertTrue(MemoryHeadroom.canLoad(
            modelBytes: model,
            availableBytes: model + MemoryHeadroom.workingOverheadBytes))
        XCTAssertFalse(MemoryHeadroom.canLoad(
            modelBytes: model,
            availableBytes: model + MemoryHeadroom.workingOverheadBytes - 1))
    }

    func testUnknownModelSizeSkipsGate() {
        // Model not on disk yet (loadContainer will download it) — size unknown.
        XCTAssertTrue(MemoryHeadroom.canLoad(modelBytes: 0, availableBytes: 1 * gb))
    }

    func testUnknownBudgetSkipsGate() {
        // os_proc_available_memory() returns 0 where no per-app budget applies.
        XCTAssertTrue(MemoryHeadroom.canLoad(modelBytes: 3 * gb, availableBytes: 0))
    }

    func testInsufficientMemoryErrorIsSpeakable() {
        let error = LocalLLMError.insufficientMemory(
            neededBytes: 4_402_341_478,   // ~4.1 GB
            availableBytes: 2_147_483_648 // 2.0 GB
        )
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("4.1 GB"))
        XCTAssertTrue(message.contains("2.0 GB"))
        XCTAssertTrue(message.contains("cloud model"))
    }
}
