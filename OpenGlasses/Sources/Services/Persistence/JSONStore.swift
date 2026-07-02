import Foundation

/// Shared load helpers for the app's JSON-blob stores (docs/plans/BB-store-integrity.md).
///
/// The invariant enforced here: **no store may ever save over data whose load failed without
/// first producing an on-disk backup.** Every JSON store loads through one of these helpers and
/// switches on the result instead of `try?`-collapsing "no data yet", "data I couldn't read",
/// and "data I couldn't decode" into one silent empty state.
enum JSONStore {

    /// Outcome of loading a persisted JSON blob.
    ///
    /// - `loaded`     — normal.
    /// - `recovered`  — the strict decode failed but elements were salvaged; the original blob
    ///                  was backed up first. Safe to continue and save.
    /// - `corrupt`    — nothing decodable; the original blob was backed up. Start fresh, but do
    ///                  not auto-save defaults over the slot — persist only on the next explicit
    ///                  user action.
    /// - `unreadable` — the bytes couldn't be read at all (e.g. file protection while the device
    ///                  is locked). The data on disk may be perfectly fine: never write.
    /// - `absent`     — genuinely no data yet (first run). Seeding defaults is safe.
    enum LoadResult<T> {
        case loaded(T)
        case recovered(T, backup: URL?)
        case corrupt(backup: URL?)
        case unreadable(Error)
        case absent

        var value: T? {
            switch self {
            case .loaded(let v), .recovered(let v, _): return v
            case .corrupt, .unreadable, .absent: return nil
            }
        }

        /// False only for `.unreadable` — the one state where the persisted bytes may be intact
        /// and writing anything would destroy data we never got to see.
        var allowsSaving: Bool {
            if case .unreadable = self { return false }
            return true
        }
    }

    /// Where corrupt blobs are preserved: `Documents/StoreRecovery/`.
    static func defaultBackupDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("StoreRecovery", isDirectory: true)
    }

    /// Preserve a blob that failed to decode as `<name>-<timestamp>.corrupt.json`. Best-effort:
    /// returns the backup URL, or nil if the backup itself couldn't be written.
    @discardableResult
    static func backUp(_ data: Data, name: String, directory: URL? = nil) -> URL? {
        let dir = directory ?? defaultBackupDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = dir.appendingPathComponent("\(name)-\(formatter.string(from: Date())).corrupt.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            NSLog("[JSONStore] Backed up undecodable %@ blob to %@", name, url.lastPathComponent)
            return url
        } catch {
            NSLog("[JSONStore] FAILED to back up %@ blob: %@", name, error.localizedDescription)
            return nil
        }
    }

    // MARK: - Decode from in-memory Data (UserDefaults-backed stores)

    /// Lenient array decode: strict first; on failure salvage element-wise (one bad element drops
    /// that element, not the collection) after backing up the original blob.
    static func decodeArray<T: Decodable>(
        _ type: T.Type, from data: Data?, name: String,
        decoder: JSONDecoder = JSONDecoder(), backupDirectory: URL? = nil
    ) -> LoadResult<[T]> {
        guard let data else { return .absent }
        if let decoded = try? decoder.decode([T].self, from: data) {
            return .loaded(decoded)
        }
        let backup = backUp(data, name: name, directory: backupDirectory)
        if let salvaged = try? decoder.decode([FailableDecodable<T>].self, from: data) {
            let values = salvaged.compactMap(\.value)
            NSLog("[JSONStore] %@: strict decode failed; salvaged %d/%d elements", name, values.count, salvaged.count)
            return .recovered(values, backup: backup)
        }
        NSLog("[JSONStore] %@: blob undecodable — starting fresh (original preserved)", name)
        return .corrupt(backup: backup)
    }

    /// Lenient string-keyed dictionary decode: strict first, then per-value salvage.
    static func decodeDictionary<V: Decodable>(
        _ type: V.Type, from data: Data?, name: String,
        decoder: JSONDecoder = JSONDecoder(), backupDirectory: URL? = nil
    ) -> LoadResult<[String: V]> {
        guard let data else { return .absent }
        if let decoded = try? decoder.decode([String: V].self, from: data) {
            return .loaded(decoded)
        }
        let backup = backUp(data, name: name, directory: backupDirectory)
        if let salvaged = try? decoder.decode([String: FailableDecodable<V>].self, from: data) {
            let values = salvaged.compactMapValues(\.value)
            NSLog("[JSONStore] %@: strict decode failed; salvaged %d/%d entries", name, values.count, salvaged.count)
            return .recovered(values, backup: backup)
        }
        NSLog("[JSONStore] %@: blob undecodable — starting fresh (original preserved)", name)
        return .corrupt(backup: backup)
    }

    // MARK: - Decode from a file (Documents/App Support stores)

    /// File-backed array load. Distinguishes a missing file (`.absent`) from a read failure
    /// (`.unreadable` — file protection, permissions), which the in-memory variants can't hit.
    static func loadArray<T: Decodable>(
        _ type: T.Type, at url: URL, name: String,
        decoder: JSONDecoder = JSONDecoder(), backupDirectory: URL? = nil
    ) -> LoadResult<[T]> {
        switch readFile(at: url, name: name) {
        case .success(let data):
            return decodeArray(type, from: data, name: name, decoder: decoder, backupDirectory: backupDirectory)
        case .failure(let outcome):
            return outcome.asResult()
        }
    }

    /// File-backed string-keyed dictionary load.
    static func loadDictionary<V: Decodable>(
        _ type: V.Type, at url: URL, name: String,
        decoder: JSONDecoder = JSONDecoder(), backupDirectory: URL? = nil
    ) -> LoadResult<[String: V]> {
        switch readFile(at: url, name: name) {
        case .success(let data):
            return decodeDictionary(type, from: data, name: name, decoder: decoder, backupDirectory: backupDirectory)
        case .failure(let outcome):
            return outcome.asResult()
        }
    }

    // MARK: - Private

    private enum ReadFailure: Error {
        case absent
        case unreadable(Error)

        func asResult<T>() -> LoadResult<T> {
            switch self {
            case .absent: return .absent
            case .unreadable(let error): return .unreadable(error)
            }
        }
    }

    private static func readFile(at url: URL, name: String) -> Result<Data, ReadFailure> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.absent) }
        do {
            return .success(try Data(contentsOf: url))
        } catch {
            NSLog("[JSONStore] %@: file exists but read failed (%@) — leaving it untouched",
                  name, error.localizedDescription)
            return .failure(.unreadable(error))
        }
    }
}

/// Wrapper that absorbs a single element's decode failure so one bad element doesn't nuke the
/// collection it lives in.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}
