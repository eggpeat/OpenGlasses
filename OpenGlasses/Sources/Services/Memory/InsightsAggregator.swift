import Foundation

/// One usage event for the insights recap.
struct InsightEvent: Equatable {
    let timestamp: Date
    let role: String          // "user" / "assistant"
    let toolNames: [String]
    let text: String
}

/// A privacy-friendly, on-device recap of how the assistant is actually used over a window.
struct InsightsReport: Equatable {
    struct Count: Equatable { let name: String; let count: Int }
    let windowStart: Date
    let windowEnd: Date
    let totalTurns: Int
    let userTurns: Int
    let topTools: [Count]
    let topTopics: [Count]
    let summary: String
}

/// Aggregates usage events into an `InsightsReport`. Pure (no network, no storage) — computed
/// entirely on-device from data already in the app. Fully unit-tested.
enum InsightsAggregator {
    /// Extra noise words on top of the recall stopwords, for topic extraction.
    private static let extraStop: Set<String> = [
        "please", "thanks", "thank", "ok", "okay", "hey", "yeah", "want", "need",
        "get", "got", "make", "show", "give", "tell", "let", "going", "just", "like",
    ]

    static func aggregate(_ events: [InsightEvent], since: Date, now: Date,
                          topN: Int = 5) -> InsightsReport {
        let inWindow = events.filter { $0.timestamp >= since && $0.timestamp <= now }
        let userEvents = inWindow.filter { $0.role == "user" }

        // Tool frequency across the window.
        var toolCounts: [String: Int] = [:]
        for event in inWindow {
            for tool in event.toolNames { toolCounts[tool, default: 0] += 1 }
        }
        let topTools = rank(toolCounts, topN: topN)

        // Topic frequency from user text (content words only).
        let stop = FTSQueryBuilder.stopwords.union(extraStop)
        var topicCounts: [String: Int] = [:]
        for event in userEvents {
            let tokens = event.text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stop.contains($0) }
            for token in Set(tokens) { topicCounts[token, default: 0] += 1 }   // once per turn
        }
        let topTopics = rank(topicCounts, topN: topN)

        return InsightsReport(
            windowStart: since, windowEnd: now,
            totalTurns: inWindow.count, userTurns: userEvents.count,
            topTools: topTools, topTopics: topTopics,
            summary: summarize(turns: inWindow.count, tools: topTools, topics: topTopics)
        )
    }

    private static func rank(_ counts: [String: Int], topN: Int) -> [InsightsReport.Count] {
        counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }   // count desc, name asc tiebreak
            .prefix(topN)
            .map { InsightsReport.Count(name: $0.key, count: $0.value) }
    }

    private static func summarize(turns: Int, tools: [InsightsReport.Count],
                                  topics: [InsightsReport.Count]) -> String {
        guard turns > 0 else { return "No activity in this window." }
        var parts = ["\(turns) turn\(turns == 1 ? "" : "s")"]
        if let top = tools.first { parts.append("most-used tool: \(top.name) (\(top.count)×)") }
        if !topics.isEmpty {
            parts.append("topics: " + topics.prefix(3).map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}
