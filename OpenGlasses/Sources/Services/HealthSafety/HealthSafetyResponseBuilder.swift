import Foundation

/// PURE composition of a health-safety answer (Plan AB). Assembles the deterministic
/// rubric hits (authoritative — surfaced first and never downgraded by the model),
/// the grounded LLM advisory (long tail, clearly labelled), the vault citation, and
/// the mandatory disclaimer. Headless-testable so "rubric authority" and "disclaimer
/// always present" are guaranteed independent of the LLM.
enum HealthSafetyResponseBuilder {

    /// The disclaimer appended to every answer.
    static let disclaimer = "This is advisory only — confirm with your pharmacist or doctor before acting."

    /// Compose the final spoken/printed answer.
    /// - Parameters:
    ///   - subject: what was asked about ("ibuprofen").
    ///   - hits: deterministic rubric hits (any order; sorted here).
    ///   - subjectRecognized: whether the catalog classified the subject at all — an
    ///     unrecognised name with no hits must never receive the authoritative
    ///     "no interactions found" absence claim.
    ///   - llmAdvisory: the grounded model answer for the long tail, or nil when unavailable.
    ///   - citations: vault sources used (e.g. ["medications", "conditions"]).
    static func compose(subject: String,
                        hits: [InteractionRubric.Hit],
                        subjectRecognized: Bool = true,
                        llmAdvisory: String?,
                        citations: [String]) -> String {
        var parts: [String] = []
        let sorted = hits.sorted { $0.severity > $1.severity }

        if sorted.contains(where: { $0.severity == .high }) {
            let reasons = sorted.filter { $0.severity == .high }.map { "• \($0.reason)" }.joined(separator: "\n")
            parts.append("⚠️ Not recommended for you (\(subject)):\n\(reasons)")
        }

        let cautions = sorted.filter { $0.severity == .caution }
        if !cautions.isEmpty {
            let reasons = cautions.map { "• \($0.reason)" }.joined(separator: "\n")
            parts.append("Caution:\n\(reasons)")
        }

        let infos = sorted.filter { $0.severity == .info }
        if !infos.isEmpty {
            parts.append(infos.map { "Note: \($0.reason)" }.joined(separator: "\n"))
        }

        if sorted.isEmpty {
            if subjectRecognized {
                parts.append("No high-severity interactions found in your vault for \(subject).")
            } else {
                parts.append("I don't recognise \(subject) in my interaction table, so I can't rule out interactions — check it with your pharmacist or doctor.")
            }
        }

        if let advisory = llmAdvisory?.trimmingCharacters(in: .whitespacesAndNewlines), !advisory.isEmpty {
            parts.append("Additional notes (advisory): \(advisory)")
        }

        if !citations.isEmpty {
            let unique = Array(NSOrderedSet(array: citations)) as? [String] ?? citations
            parts.append("Source: your \(unique.joined(separator: ", ")) vault entries.")
        }

        parts.append(disclaimer)
        return parts.joined(separator: "\n\n")
    }

    /// Whether the rubric produced an authoritative high-severity warning — the model
    /// must never be allowed to contradict this.
    static func hasAuthoritativeWarning(_ hits: [InteractionRubric.Hit]) -> Bool {
        hits.contains { $0.severity == .high }
    }
}
