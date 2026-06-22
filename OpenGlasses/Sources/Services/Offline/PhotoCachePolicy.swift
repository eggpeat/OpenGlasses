import Foundation

/// Disk-pressure cap for synced photo evidence (Plan T). Photos captured offline are kept on disk
/// until their upload op is `done`; once delivered they're just a cache, so under disk pressure we
/// evict the **oldest delivered** ones first until back under budget. Pure → fully unit-tested; the
/// queue supplies real file sizes and does the deletion.
enum PhotoCachePolicy {
    struct Entry: Equatable {
        let id: String
        let sizeBytes: Int
        let createdAt: Date
    }

    /// Ids to evict so the total drops to ≤ `maxBytes`, oldest first. Empty when already under budget.
    static func evictions(_ entries: [Entry], maxBytes: Int) -> [String] {
        let total = entries.reduce(0) { $0 + $1.sizeBytes }
        guard total > maxBytes else { return [] }

        var overflow = total - maxBytes
        var evict: [String] = []
        for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {   // oldest first
            if overflow <= 0 { break }
            evict.append(entry.id)
            overflow -= entry.sizeBytes
        }
        return evict
    }
}
