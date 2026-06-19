import Foundation

/// A specific unsafe condition the model localised, with a normalized bounding box
/// (`box_2d = [ymin, xmin, ymax, xmax]`, 0–1000).
struct EvidenceBox: Codable, Equatable {
    let note: String
    let box: [Int]
}

/// One hazard's finding within a HECA. The model decides `has_*_control` directly, so control status
/// doesn't hinge on a non-empty-string heuristic.
struct HazardFinding: Codable, Equatable, Identifiable {
    let hazard: HighEnergyHazard
    let isPresent: Bool
    let hasDirectControl: Bool
    let directControl: String
    let hasIndirectControl: Bool
    let indirectControl: String
    let comments: String
    let evidence: [EvidenceBox]

    var id: String { hazard.rawValue }

    var controlStatus: ControlStatus {
        hasDirectControl ? .direct : (hasIndirectControl ? .indirect : .none)
    }

    init(hazard: HighEnergyHazard, isPresent: Bool = false,
         hasDirectControl: Bool = false, directControl: String = "",
         hasIndirectControl: Bool = false, indirectControl: String = "",
         comments: String = "", evidence: [EvidenceBox] = []) {
        self.hazard = hazard
        self.isPresent = isPresent
        self.hasDirectControl = hasDirectControl
        self.directControl = directControl
        self.hasIndirectControl = hasIndirectControl
        self.indirectControl = indirectControl
        self.comments = comments
        self.evidence = evidence
    }
}

/// A High-Energy Control Assessment report — all 13 hazards (present or not) plus the HECA score.
struct SafetyReport: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let summary: String
    let findings: [HazardFinding]   // all 13, present or not

    /// Present hazards.
    var present: [HazardFinding] { findings.filter(\.isPresent) }

    /// Present hazards lacking a *direct* control — the SIF risks worth surfacing first.
    var uncontrolled: [HazardFinding] { present.filter { $0.controlStatus != .direct } }

    /// The single highest-priority uncontrolled hazard (none-control before indirect-only).
    var topUncontrolled: HazardFinding? {
        uncontrolled.sorted { a, b in
            (a.controlStatus == .none ? 0 : 1) < (b.controlStatus == .none ? 0 : 1)
        }.first
    }

    /// HECA score = present hazards with a direct control / present hazards. nil if none present.
    var score: Double? {
        let p = present
        guard !p.isEmpty else { return nil }
        return Double(p.filter { $0.controlStatus == .direct }.count) / Double(p.count)
    }

    // MARK: - Decoding from model JSON

    private struct DTO: Decodable {
        let summary: String?
        let assessments: [Item]?
        struct Item: Decodable {
            let category: String
            let isPresent: Bool?
            let hasDirectControl: Bool?
            let directControl: String?
            let hasIndirectControl: Bool?
            let indirectControl: String?
            let comments: String?
            let evidence: [Ev]?
            struct Ev: Decodable {
                let note: String?
                let box2d: [Int]?
                enum CodingKeys: String, CodingKey { case note; case box2d = "box_2d" }
            }
            enum CodingKeys: String, CodingKey {
                case category
                case isPresent = "is_present"
                case hasDirectControl = "has_direct_control"
                case directControl = "direct_control"
                case hasIndirectControl = "has_indirect_control"
                case indirectControl = "indirect_control"
                case comments, evidence
            }
        }
    }

    /// Decode + validate the `{ summary, assessments: [...] }` model output into a report. Unknown
    /// category ids are ignored; any of the 13 the model omitted are filled in as not-present, so the
    /// report always contains exactly the 13 canonical hazards.
    static func from(json: [String: Any], id: String = UUID().uuidString, createdAt: Date = Date()) throws -> SafetyReport {
        let dto: DTO
        do { dto = try AssessmentJSON.decode(DTO.self, from: json) }
        catch { throw AssessmentSchemaError.malformedPayload("safety_assessment: \(error)") }

        var byHazard: [HighEnergyHazard: HazardFinding] = [:]
        for item in dto.assessments ?? [] {
            guard let hazard = HighEnergyHazard(rawValue: item.category) else { continue }  // ignore unknown ids
            byHazard[hazard] = HazardFinding(
                hazard: hazard,
                isPresent: item.isPresent ?? false,
                hasDirectControl: item.hasDirectControl ?? false,
                directControl: item.directControl ?? "",
                hasIndirectControl: item.hasIndirectControl ?? false,
                indirectControl: item.indirectControl ?? "",
                comments: item.comments ?? "",
                evidence: (item.evidence ?? []).compactMap { ev in
                    guard let box = ev.box2d, box.count == 4 else { return nil }
                    return EvidenceBox(note: ev.note ?? "", box: box)
                })
        }
        // Always return all 13 in canonical order, filling gaps as not-present.
        let findings = HighEnergyHazard.allCases.map { byHazard[$0] ?? HazardFinding(hazard: $0) }
        return SafetyReport(id: id, createdAt: createdAt,
                            summary: dto.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                            findings: findings)
    }
}
