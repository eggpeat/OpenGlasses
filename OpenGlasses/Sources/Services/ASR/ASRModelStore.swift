import Foundation

/// Download/availability state of the on-device ASR model.
enum ASRModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case verifying
    case ready
    case failed(reason: String)
}

/// Tracks whether the SenseVoice model (`ASRModelBundle`) is present in Application Support (Additional
/// Capabilities #8). On-device ASR is a **no-op until the model is present** — the int8 model is ~240 MB,
/// so it's downloaded on first enable rather than bundled (avoids binary bloat), mirroring the Kokoro
/// tier's discipline.
///
/// Pure file-system bookkeeping — injectable `directory` makes presence/selection fully unit-testable.
struct ASRModelStore {

    let bundle: ASRModelBundle
    let directory: URL
    private let fileManager: FileManager

    init(bundle: ASRModelBundle = .active, directory: URL? = nil, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(for: bundle, fileManager: fileManager)
    }

    /// `Application Support/<bundle.directoryName>` (falls back to a temp dir if Application Support is
    /// somehow unavailable — defensive; never expected in practice).
    static func defaultDirectory(for bundle: ASRModelBundle, fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(bundle.directoryName, isDirectory: true)
    }

    func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Present only if the file exists, is a file, and is **non-empty** (a truncated download leaves a
    /// 0-byte stub that must not pass as installed).
    func isFilePresent(_ name: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL(name).path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let size = (try? fileManager.attributesOfItem(atPath: fileURL(name).path)[.size]) as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }

    var missingFiles: [String] { bundle.requiredFiles.filter { !isFilePresent($0) } }
    var isModelPresent: Bool { missingFiles.isEmpty }
    var state: ASRModelState { isModelPresent ? .ready : .notDownloaded }

    func totalBytesOnDisk() -> Int64 {
        bundle.requiredFiles.reduce(into: Int64(0)) { sum, name in
            if let size = try? fileManager.attributesOfItem(atPath: fileURL(name).path)[.size] as? NSNumber {
                sum += size.int64Value
            }
        }
    }

    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func deleteModel() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
