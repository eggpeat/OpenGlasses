import Foundation

/// Persists study decks and per-card Leitner review records (docs/plans/study-mode.md). Two JSON files
/// under Application Support; directory + FileManager injectable for tests.
@MainActor
final class StudyStore: ObservableObject {
    static let shared = StudyStore()

    @Published private(set) var decks: [StudyDeck] = []

    private var reviews: [String: ReviewRecord] = [:]   // cardID → record
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        load()
    }

    static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("StudyDecks", isDirectory: true)
    }

    private var decksURL: URL { directory.appendingPathComponent("decks.json") }
    private var reviewsURL: URL { directory.appendingPathComponent("reviews.json") }

    // MARK: - Decks

    func saveDeck(_ deck: StudyDeck) {
        decks.removeAll { $0.id == deck.id }
        decks.insert(deck, at: 0)
        persistDecks()
    }

    func deck(id: String) -> StudyDeck? { decks.first { $0.id == id } }

    func deleteDeck(id: String) {
        decks.removeAll { $0.id == id }
        persistDecks()
    }

    // MARK: - Review records

    func reviewRecord(cardID: String) -> ReviewRecord? { reviews[cardID] }

    func saveReviewRecord(_ record: ReviewRecord) {
        reviews[record.cardID] = record
        persistReviews()
    }

    var allReviewRecords: [ReviewRecord] { Array(reviews.values) }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: decksURL),
           let d = try? JSONDecoder().decode([StudyDeck].self, from: data) {
            decks = d
        }
        if let data = try? Data(contentsOf: reviewsURL),
           let r = try? JSONDecoder().decode([String: ReviewRecord].self, from: data) {
            reviews = r
        }
    }

    private func persistDecks() { write(decks, to: decksURL) }
    private func persistReviews() { write(reviews, to: reviewsURL) }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("[StudyStore] persist failed: %@", error.localizedDescription)
        }
    }
}
