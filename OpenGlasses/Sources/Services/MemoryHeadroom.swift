import Foundation
import os

/// App memory telemetry + the pure admission rule for loading on-device models.
///
/// Why this exists: a model bigger than the app's remaining allocation budget doesn't
/// fail cleanly — the load (or the first generation) drives the device into compressor
/// thrashing and a silent Jetsam kill with no crash report. Observed 2026-07-13:
/// gemma-4-e2b (3.6 GB weights) at 3.1 GB resident left 0.16 GB free device-wide and
/// the kernel logged a vm-compressor-thrashing event. Checking headroom *before*
/// loading turns that into a catchable, speakable error.
///
/// iOS sandboxing means an app can only see its own memory — footprint via
/// `task_vm_info` and remaining budget via `os_proc_available_memory()`. Per-app
/// comparisons across the system only exist retrospectively in JetsamEvent logs.
enum MemoryHeadroom {

    /// Working overhead a loaded model needs beyond its weights: KV cache, activations,
    /// and Metal buffers during generation. Sized from the 2026-07-13 Jetsam data
    /// (weights-sized footprint plus ~0.5–1 GB of generation-time growth).
    static let workingOverheadBytes: Int64 = 768 * 1024 * 1024

    /// Pure admission rule (headless-testable): can a model of `modelBytes` load when
    /// the app can still allocate `availableBytes` before its jetsam limit?
    ///
    /// Unknown values (≤ 0) skip the gate rather than block: `modelBytes` is 0 when the
    /// model isn't on disk yet, and `os_proc_available_memory()` returns 0 on platforms
    /// where the budget doesn't apply (simulator, Mac). Refusing on "unknown" would
    /// brick loading in exactly the environments that don't need the guard.
    static func canLoad(modelBytes: Int64, availableBytes: Int64) -> Bool {
        guard modelBytes > 0, availableBytes > 0 else { return true }
        return availableBytes >= modelBytes + workingOverheadBytes
    }

    /// Bytes this process currently occupies — `phys_footprint`, the same number
    /// Xcode's memory gauge and the jetsam accounting use.
    static func appFootprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.phys_footprint)
    }

    /// Bytes the app can still allocate before iOS terminates it. 0 = no budget on
    /// this platform (simulator/Mac).
    static func availableBytes() -> Int64 {
        Int64(os_proc_available_memory())
    }
}
