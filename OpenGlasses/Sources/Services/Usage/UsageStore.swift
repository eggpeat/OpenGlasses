import Foundation
import SQLite3

/// Durable, append-only store of `UsageRecord`s, backed by SQLite (Plan AU) — the
/// same storage family as `OfflineQueue`/`SemanticMemoryStore`. Local-only; nothing
/// leaves the device. Rows are inserted once and never mutated.
@MainActor
final class UsageStore {
    private var db: OpaquePointer?

    /// `path` is injectable so tests can use a throwaway file (and reopen it to prove survival).
    init(path: URL? = nil) {
        let url = path ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("usage.sqlite")
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            NSLog("[UsageStore] Failed to open database at %@", url.path)
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
        CREATE TABLE IF NOT EXISTS usage (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            tokens_in INTEGER NOT NULL,
            tokens_out INTEGER NOT NULL,
            cost_usd REAL,
            at REAL NOT NULL
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_usage_at ON usage(at)")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Mutations

    /// Persist a usage record. `cost_usd` is stored NULL when the model was unpriced.
    func insert(_ record: UsageRecord) {
        let sql = "INSERT OR REPLACE INTO usage (id, session_id, provider, model, tokens_in, tokens_out, cost_usd, at) " +
                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, record.id)
        bindText(stmt, 2, record.sessionId)
        bindText(stmt, 3, record.provider)
        bindText(stmt, 4, record.model)
        sqlite3_bind_int(stmt, 5, Int32(record.tokensIn))
        sqlite3_bind_int(stmt, 6, Int32(record.tokensOut))
        if let cost = record.costUSD {
            sqlite3_bind_double(stmt, 7, cost)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_double(stmt, 8, record.at.timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    /// Test/maintenance helper: wipe everything.
    func deleteAll() {
        exec("DELETE FROM usage")
    }

    // MARK: - Queries

    /// All records with `at >= since`, newest first.
    func records(since: Date) -> [UsageRecord] {
        query("SELECT id, session_id, provider, model, tokens_in, tokens_out, cost_usd, at FROM usage " +
              "WHERE at >= \(since.timeIntervalSince1970) ORDER BY at DESC")
    }

    /// Convenience: rolled-up totals over the last `days`, computed by `UsageRollup`.
    func rollup(days: Int, now: Date = Date()) -> UsageRollup.Result {
        let since = now.addingTimeInterval(-Double(max(0, days)) * 86_400)
        return UsageRollup.rollup(records(since: since), since: since)
    }

    // MARK: - SQLite plumbing

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)  // SQLITE_TRANSIENT

    private func query(_ sql: String) -> [UsageRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [UsageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let sessionId = String(cString: sqlite3_column_text(stmt, 1))
            let provider = String(cString: sqlite3_column_text(stmt, 2))
            let model = String(cString: sqlite3_column_text(stmt, 3))
            let tokensIn = Int(sqlite3_column_int(stmt, 4))
            let tokensOut = Int(sqlite3_column_int(stmt, 5))
            let cost: Double? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 6)
            let at = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            out.append(UsageRecord(id: id, sessionId: sessionId, provider: provider, model: model,
                                   tokensIn: tokensIn, tokensOut: tokensOut, costUSD: cost, at: at))
        }
        return out
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, Self.transient)
    }
}
