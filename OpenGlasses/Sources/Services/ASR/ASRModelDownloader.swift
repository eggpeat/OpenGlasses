import Foundation

/// Failure modes of the ASR model download.
enum ASRDownloadError: LocalizedError, Equatable {
    case incompleteDownload(missing: String)

    var errorDescription: String? {
        switch self {
        case .incompleteDownload(let missing):
            return "Downloaded model is incomplete (missing: \(missing))"
        }
    }
}

/// Orchestrates first-enable download of the SenseVoice model into Application Support (Additional
/// Capabilities #8). The deterministic core — the state machine plus download-to-staging → verify →
/// atomic-install — is driven through an **injected installer**, so it's fully unit-tested headlessly
/// with a fake. The default installer fetches each required file from HuggingFace with URLSession
/// (the files are unpacked, so there's nothing to enumerate or extract).
@MainActor
final class ASRModelDownloader: ObservableObject {

    typealias ProgressHandler = @MainActor (Double) -> Void
    /// Fetches `bundle`'s files into `destination` (a staging directory), reporting progress.
    typealias Installer = (_ bundle: ASRModelBundle,
                           _ destination: URL,
                           _ progress: @escaping ProgressHandler) async throws -> Void

    @Published private(set) var state: ASRModelState

    private let bundle: ASRModelBundle
    private let modelDirectory: URL
    private let fileManager: FileManager
    private let installer: Installer

    init(bundle: ASRModelBundle = .active,
         modelDirectory: URL? = nil,
         fileManager: FileManager = .default,
         installer: @escaping Installer = ASRModelDownloader.liveInstaller) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.modelDirectory = modelDirectory ?? ASRModelStore.defaultDirectory(for: bundle, fileManager: fileManager)
        self.installer = installer
        self.state = ASRModelStore(bundle: bundle, directory: self.modelDirectory, fileManager: fileManager).state
    }

    private var store: ASRModelStore {
        ASRModelStore(bundle: bundle, directory: modelDirectory, fileManager: fileManager)
    }

    func refreshState() {
        if case .downloading = state { return }
        state = store.state
    }

    /// Download + install. Idempotent (no-op → `.ready` when already present). Stages into a sibling
    /// directory and only atomically swaps it into place once it verifies, so a partial/failed download
    /// never half-installs.
    func download() async {
        if store.isModelPresent { state = .ready; return }

        state = .downloading(progress: 0)
        let staging = modelDirectory.deletingLastPathComponent()
            .appendingPathComponent("\(bundle.directoryName)-staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try? fileManager.removeItem(at: staging)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

            try await installer(bundle, staging) { [weak self] fraction in
                self?.state = .downloading(progress: min(max(fraction, 0), 1))
            }

            state = .verifying
            let staged = ASRModelStore(bundle: bundle, directory: staging, fileManager: fileManager)
            guard staged.isModelPresent else {
                throw ASRDownloadError.incompleteDownload(missing: staged.missingFiles.joined(separator: ", "))
            }

            try? fileManager.removeItem(at: modelDirectory)
            try fileManager.createDirectory(at: modelDirectory.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: staging, to: modelDirectory)
            state = .ready
        } catch {
            try? fileManager.removeItem(at: staging)
            state = .failed(reason: (error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    func deleteModel() {
        try? store.deleteModel()
        state = store.state
    }

    // MARK: - Live installer

    /// Fetches each required file directly from HuggingFace (the files are unpacked, so no tree
    /// enumeration). Progress is per-file completed fraction.
    static let liveInstaller: Installer = { bundle, destination, progress in
        let files = bundle.requiredFiles
        for (index, name) in files.enumerated() {
            let url = bundle.huggingFaceResolveURL(for: name)
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ASRDownloadError.incompleteDownload(missing: "\(name) (HTTP \(http.statusCode))")
            }
            let dest = destination.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            await progress(Double(index + 1) / Double(max(files.count, 1)))
        }
    }
}
