import Foundation

/// Loads `CaptureFlow` definitions from a vault's `flows/` directory (Plan U) — mirroring how
/// `ProcedureLibrary` loads `procedures/`. Merges the bundled baseline with the user overlay, the
/// overlay winning, so authored/edited flows shadow the shipped ones.
struct CaptureFlowLibrary {
    let vaultId: String
    private let flows: [CaptureFlow]
    /// "filename: reason" for each flow file that failed to load (BM P2) — surfaced by the
    /// `capture_flow` tool's `list` action so a typo'd overlay never silently vanishes.
    let rejected: [String]

    /// Build from a vault store. Returns an empty library if the vault has no `flows/` content.
    init(store: VaultStore) {
        vaultId = store.manifest.id
        (flows, rejected) = Self.loadStrict(
            bundleDir: store.bundleRoot?.appendingPathComponent("flows", isDirectory: true),
            overlayDir: store.overlayRoot.appendingPathComponent("flows", isDirectory: true))
    }

    /// Test / explicit init.
    init(vaultId: String, flows: [CaptureFlow]) {
        self.vaultId = vaultId
        self.flows = flows
        self.rejected = []
    }

    var all: [CaptureFlow] { flows }
    var isEmpty: Bool { flows.isEmpty }

    func flow(id: String) -> CaptureFlow? { flows.first { $0.id == id } }

    /// "id — title" summaries for prompts / `list` actions.
    func summaries() -> [String] { flows.map { "\($0.id) — \($0.title)" } }

    // MARK: - Loading

    /// Decode a single flow from JSON data (nil on malformed input).
    static func decode(_ data: Data) -> CaptureFlow? {
        decodeReporting(data).flow
    }

    /// Decode a single flow, returning a human-readable rejection reason on failure — the
    /// `MCPCatalog.loadStrict` pattern (BM P2). A file declaring a `schema_version` newer than
    /// `CaptureFlow.currentSchemaVersion` is rejected without attempting a full decode, so a
    /// v2 flow reads as "too new", not as a pile of decoding errors.
    static func decodeReporting(_ data: Data) -> (flow: CaptureFlow?, rejection: String?) {
        let decoder = JSONDecoder()
        if let probe = try? decoder.decode(VersionProbe.self, from: data),
           let version = probe.schemaVersion, version > CaptureFlow.currentSchemaVersion {
            return (nil, "schema_version \(version) is newer than this app supports (\(CaptureFlow.currentSchemaVersion))")
        }
        do {
            return (try decoder.decode(CaptureFlow.self, from: data), nil)
        } catch {
            return (nil, rejectionReason(from: error))
        }
    }

    /// Load every `*.json` flow from a directory (overlay wins over bundle by filename).
    static func load(bundleDir: URL?, overlayDir: URL?) -> [CaptureFlow] {
        loadStrict(bundleDir: bundleDir, overlayDir: overlayDir).flows
    }

    /// As `load`, additionally reporting every file that failed ("filename: reason") instead of
    /// silently dropping it.
    static func loadStrict(bundleDir: URL?, overlayDir: URL?) -> (flows: [CaptureFlow], rejected: [String]) {
        var byFilename: [String: URL] = [:]
        if let bundleDir {
            for url in jsonFiles(in: bundleDir) { byFilename[url.lastPathComponent] = url }
        }
        if let overlayDir {
            for url in jsonFiles(in: overlayDir) { byFilename[url.lastPathComponent] = url }
        }
        var flows: [CaptureFlow] = []
        var rejected: [String] = []
        for (filename, url) in byFilename.sorted(by: { $0.key < $1.key }) {
            guard let data = try? Data(contentsOf: url) else {
                rejected.append("\(filename): unreadable")
                continue
            }
            let (flow, rejection) = decodeReporting(data)
            if let flow {
                flows.append(flow)
            } else {
                rejected.append("\(filename): \(rejection ?? "not valid flow JSON")")
            }
        }
        return (flows.sorted { $0.id < $1.id }, rejected)
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int?
        enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version" }
    }

    private static func rejectionReason(from error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let ctx),
             DecodingError.typeMismatch(_, let ctx),
             DecodingError.valueNotFound(_, let ctx):
            return readable(ctx)
        case DecodingError.keyNotFound(let key, let ctx):
            let path = pathString(ctx.codingPath)
            return "missing required field '\(key.stringValue)'\(path.isEmpty ? "" : " at \(path)")"
        default:
            return "not valid flow JSON"
        }
    }

    private static func readable(_ ctx: DecodingError.Context) -> String {
        let path = pathString(ctx.codingPath)
        return path.isEmpty ? ctx.debugDescription : "\(path): \(ctx.debugDescription)"
    }

    private static func pathString(_ codingPath: [CodingKey]) -> String {
        codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    private static func jsonFiles(in dir: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return entries.filter { $0.pathExtension.lowercased() == "json" }
    }
}
