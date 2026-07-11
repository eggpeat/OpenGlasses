import Foundation

/// PURE, curated table of well-established **high-severity** interactions and
/// contraindications (Plan AB). Authoritative when it fires — the LLM is never
/// allowed to downgrade a hit to "safe". Deliberately NOT exhaustive; the model
/// covers the long tail. Each hit cites a clinical basis.
struct InteractionRubric {

    enum Severity: Int, Comparable {
        case info, caution, high
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Hit: Equatable {
        let reason: String
        let severity: Severity
        let basis: String
    }

    /// Check a queried substance (for "can I take X?") against the user's grounded
    /// vault context. Returns every rule that fires, highest-severity first.
    func check(_ substance: Substance, against context: GroundingContext) -> [Hit] {
        var hits: [Hit] = []
        let userClasses = context.drugClassesInUse

        // Allergy match — a substance the user is allergic to. Always high.
        if matchesAllergy(substance, allergies: context.allergies) {
            hits.append(Hit(reason: "This matches an allergy recorded in your vault.",
                            severity: .high, basis: "recorded allergy"))
        }

        // NSAID + anticoagulant → major bleeding risk. Fires on the drug class OR the
        // condition tag ("on blood thinners" in conditions.md with no recognised drug name).
        if substance.classes.contains(.nsaid),
           userClasses.contains(.anticoagulant) || context.conditions.contains(.anticoagulated) {
            hits.append(Hit(reason: "You take a blood thinner; an NSAID markedly raises bleeding risk.",
                            severity: .high, basis: "NSAID + anticoagulant → GI/bleeding risk"))
        }
        // NSAID + peptic ulcer → high.
        if substance.classes.contains(.nsaid), context.conditions.contains(.pepticUlcer) {
            hits.append(Hit(reason: "You have a peptic ulcer history; NSAIDs can cause GI bleeding.",
                            severity: .high, basis: "NSAID + peptic ulcer"))
        }
        // NSAID + asthma → caution (aspirin-exacerbated respiratory disease: NSAIDs can
        // trigger severe bronchospasm in a subset of people with asthma).
        if substance.classes.contains(.nsaid), context.conditions.contains(.asthma) {
            hits.append(Hit(reason: "You have asthma; NSAIDs can trigger severe breathing problems in some people with asthma.",
                            severity: .caution, basis: "NSAID + asthma (aspirin-exacerbated respiratory disease)"))
        }
        // NSAID + kidney disease → caution.
        if substance.classes.contains(.nsaid), context.conditions.contains(.kidneyDisease) {
            hits.append(Hit(reason: "You have kidney disease; NSAIDs can worsen renal function.",
                            severity: .caution, basis: "NSAID + CKD"))
        }
        // NSAID + ACE/ARB → caution (renal "triple whammy" precursor).
        if substance.classes.contains(.nsaid), !userClasses.isDisjoint(with: [.aceInhibitor, .arb]) {
            hits.append(Hit(reason: "An NSAID with your blood-pressure medication can reduce kidney function and raise blood pressure.",
                            severity: .caution, basis: "NSAID + ACE inhibitor/ARB"))
        }
        // Potassium-sparing diuretic / ACE / ARB + extra potassium handled in food check.

        // SSRI + NSAID/anticoagulant → caution (bleeding).
        if substance.classes.contains(.nsaid), userClasses.contains(.ssri) {
            hits.append(Hit(reason: "An SSRI with an NSAID modestly raises bleeding risk.",
                            severity: .caution, basis: "SSRI + NSAID"))
        }

        // MAOI + SSRI → serotonin syndrome (drug-drug, either direction).
        if pair(substance, userClasses, .maoi, .ssri) {
            hits.append(Hit(reason: "Combining an MAOI and an SSRI can cause serotonin syndrome.",
                            severity: .high, basis: "MAOI + SSRI → serotonin syndrome"))
        }
        // PDE5 inhibitor + nitrate → severe hypotension.
        if pair(substance, userClasses, .pde5Inhibitor, .nitrate) {
            hits.append(Hit(reason: "An erectile-dysfunction drug with a nitrate can drop your blood pressure dangerously.",
                            severity: .high, basis: "PDE5 inhibitor + nitrate → hypotension"))
        }
        // Methotrexate + NSAID → methotrexate toxicity.
        if pair(substance, userClasses, .methotrexate, .nsaid) {
            hits.append(Hit(reason: "An NSAID can raise methotrexate to toxic levels.",
                            severity: .high, basis: "methotrexate + NSAID → toxicity"))
        }
        // Opioid/benzodiazepine combined → additive respiratory depression.
        if pair(substance, userClasses, .opioid, .benzodiazepine)
            || (substance.classes.contains(.opioid) && userClasses.contains(.opioid))
            || (substance.classes.contains(.benzodiazepine) && userClasses.contains(.benzodiazepine)) {
            hits.append(Hit(reason: "Combining sedatives (opioids and/or benzodiazepines) can dangerously slow your breathing.",
                            severity: .high, basis: "opioid + benzodiazepine → respiratory depression"))
        }
        // Lithium + NSAID → lithium toxicity.
        if pair(substance, userClasses, .lithium, .nsaid) {
            hits.append(Hit(reason: "An NSAID can raise lithium to toxic levels.",
                            severity: .high, basis: "lithium + NSAID → toxicity"))
        }
        // ACE/ARB + potassium-sparing diuretic → hyperkalemia (drug-drug).
        if (!substance.classes.isDisjoint(with: [.aceInhibitor, .arb]) && userClasses.contains(.potassiumSparingDiuretic))
            || (substance.classes.contains(.potassiumSparingDiuretic) && !userClasses.isDisjoint(with: [.aceInhibitor, .arb])) {
            hits.append(Hit(reason: "This combination with your blood-pressure medication can raise potassium to dangerous levels.",
                            severity: .high, basis: "ACE/ARB + potassium-sparing diuretic → hyperkalemia"))
        }
        // NSAID in pregnancy → caution (avoid, esp. third trimester).
        if substance.classes.contains(.nsaid), context.conditions.contains(.pregnancy) {
            hits.append(Hit(reason: "NSAIDs are generally avoided in pregnancy — check with your doctor.",
                            severity: .caution, basis: "NSAID + pregnancy"))
        }

        return hits.sorted { $0.severity > $1.severity }
    }

    /// True when the dangerous pair (`a`,`b`) is split across the queried substance and
    /// the user's current meds, in either direction.
    private func pair(_ substance: Substance, _ user: Set<DrugClass>, _ a: DrugClass, _ b: DrugClass) -> Bool {
        (substance.classes.contains(a) && user.contains(b)) || (substance.classes.contains(b) && user.contains(a))
    }

    /// Check a food (for "can I eat this?") — its tags against the user's meds/conditions.
    func checkFood(_ tags: Set<FoodTag>, against context: GroundingContext) -> [Hit] {
        var hits: [Hit] = []
        let userClasses = context.drugClassesInUse

        // MAOI + tyramine → hypertensive crisis.
        if tags.contains(.tyramineRich), userClasses.contains(.maoi) {
            hits.append(Hit(reason: "You take an MAOI; tyramine-rich foods can trigger a dangerous blood-pressure spike.",
                            severity: .high, basis: "MAOI + tyramine → hypertensive crisis"))
        }
        // Warfarin + vitamin K → reduced anticoagulation.
        if tags.contains(.vitaminKRich), userClasses.contains(.anticoagulant) {
            hits.append(Hit(reason: "Large changes in vitamin-K-rich foods can offset your blood thinner; keep intake consistent.",
                            severity: .caution, basis: "warfarin + vitamin K"))
        }
        // ACE/ARB/K-sparing diuretic + potassium → hyperkalemia.
        if tags.contains(.potassiumRich), !userClasses.isDisjoint(with: [.aceInhibitor, .arb, .potassiumSparingDiuretic]) {
            hits.append(Hit(reason: "Your medication raises potassium; large amounts of potassium-rich food can push it too high.",
                            severity: .caution, basis: "ACE/ARB/K-sparing diuretic + potassium"))
        }
        // High sodium + hypertension → caution.
        if tags.contains(.highSodium), context.conditions.contains(.hypertension) {
            hits.append(Hit(reason: "You have high blood pressure; high-sodium foods can worsen it.",
                            severity: .caution, basis: "high sodium + hypertension"))
        }
        // Purine-rich + gout → caution.
        if tags.contains(.purineRich), context.conditions.contains(.gout) {
            hits.append(Hit(reason: "You have gout; purine-rich foods can trigger a flare.",
                            severity: .caution, basis: "purine-rich + gout"))
        }
        // Alcohol + sedatives → additive CNS/respiratory depression.
        if tags.contains(.alcohol), !userClasses.isDisjoint(with: [.opioid, .benzodiazepine]) {
            hits.append(Hit(reason: "Alcohol with your sedative medication can dangerously slow breathing and heavy sedation.",
                            severity: .high, basis: "alcohol + opioid/benzodiazepine"))
        }
        // Statin + grapefruit → raised statin levels (muscle injury risk).
        if tags.contains(.grapefruit), userClasses.contains(.statin) {
            hits.append(Hit(reason: "Grapefruit can raise your statin levels and the risk of muscle injury.",
                            severity: .caution, basis: "statin + grapefruit"))
        }
        // Grapefruit + other meds → general CYP3A4 flag.
        if tags.contains(.grapefruit), !userClasses.isEmpty {
            hits.append(Hit(reason: "Grapefruit can change how some medications are absorbed — check this one specifically.",
                            severity: .info, basis: "grapefruit + CYP3A4 substrates"))
        }

        return hits.sorted { $0.severity > $1.severity }
    }

    // MARK: - Helpers

    private func matchesAllergy(_ substance: Substance, allergies: [String]) -> Bool {
        let name = substance.raw.lowercased()
        guard name.count >= 3 else { return false }
        return allergies.contains { allergy in
            allergy.contains(name) || name.split(separator: " ").contains { word in
                word.count >= 4 && allergy.contains(word)
            }
        }
    }
}
