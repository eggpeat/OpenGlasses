import XCTest
@testable import OpenGlasses

final class HealthSafetyTests: XCTestCase {

    // MARK: - SubstanceCatalog

    func testDrugClassification() {
        XCTAssertEqual(SubstanceCatalog.substance(from: "Ibuprofen 200mg").classes, [.nsaid])
        XCTAssertEqual(SubstanceCatalog.substance(from: "Warfarin 5mg daily").classes, [.anticoagulant])
        XCTAssertEqual(SubstanceCatalog.substance(from: "Lisinopril").classes, [.aceInhibitor])
        XCTAssertEqual(SubstanceCatalog.substance(from: "Nardil (phenelzine)").classes, [.maoi])
        XCTAssertTrue(SubstanceCatalog.substance(from: "vitamin C").classes.isEmpty)
    }

    func testFoodAndConditionTags() {
        XCTAssertTrue(SubstanceCatalog.foodTags(in: "aged cheddar cheese").contains(.tyramineRich))
        XCTAssertTrue(SubstanceCatalog.foodTags(in: "fresh spinach salad").contains(.vitaminKRich))
        XCTAssertTrue(SubstanceCatalog.foodTags(in: "banana smoothie").contains(.potassiumRich))
        XCTAssertTrue(SubstanceCatalog.conditionTags(in: "History of peptic ulcer").contains(.pepticUlcer))
        XCTAssertTrue(SubstanceCatalog.conditionTags(in: "CKD stage 3").contains(.kidneyDisease))
    }

    // MARK: - VaultGrounding

    private let meds = """
    # Medications
    - Warfarin 5mg once daily
    - Metformin 500mg twice daily
    """
    private let conditions = "## Conditions\n- Atrial fibrillation\n- History of peptic ulcer"
    private let allergies = "- Penicillin\n- Sulfa drugs"

    func testGroundingExtractsMedClassesAndConditions() {
        let g = VaultGrounding()
        let ctx = g.relevantEntries(
            for: HealthSafetyQuery(kind: .canITake, subject: "ibuprofen"),
            medicationsText: meds, conditionsText: conditions, allergiesText: allergies)
        XCTAssertTrue(ctx.drugClassesInUse.contains(.anticoagulant))
        XCTAssertTrue(ctx.conditions.contains(.pepticUlcer))
        // Allergies are always carried.
        XCTAssertEqual(ctx.allergies.count, 2)
    }

    func testGroundingAlwaysIncludesAllergiesEvenWhenUnrelated() {
        let g = VaultGrounding()
        let ctx = g.relevantEntries(
            for: HealthSafetyQuery(kind: .canITake, subject: "penicillin"),
            medicationsText: meds, conditionsText: conditions, allergiesText: allergies)
        XCTAssertTrue(ctx.allergies.contains { $0.contains("penicillin") })
    }

    // MARK: - InteractionRubric (can I take X)

    private func context(meds: [DrugClass], conditions: Set<ConditionTag> = [], allergies: [String] = []) -> GroundingContext {
        GroundingContext(
            medications: meds.map { Substance(raw: $0.rawValue, classes: [$0]) },
            conditions: conditions, allergies: allergies, citedLines: [])
    }

    func testWarfarinPlusNSAIDIsHigh() {
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "ibuprofen"),
            against: context(meds: [.anticoagulant]))
        XCTAssertTrue(hits.contains { $0.severity == .high })
    }

    func testNSAIDPlusPepticUlcerIsHigh() {
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "naproxen"),
            against: context(meds: [], conditions: [.pepticUlcer]))
        XCTAssertEqual(hits.first?.severity, .high)
    }

    func testAllergyMatchIsHigh() {
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "penicillin"),
            against: context(meds: [], allergies: ["penicillin", "sulfa drugs"]))
        XCTAssertTrue(hits.contains { $0.severity == .high && $0.basis == "recorded allergy" })
    }

    func testUnrelatedPairingHasNoHit() {
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "vitamin c"),
            against: context(meds: [.aceInhibitor]))
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - InteractionRubric (can I eat this)

    func testMAOIPlusTyramineIsHigh() {
        let hits = InteractionRubric().checkFood([.tyramineRich], against: context(meds: [.maoi]))
        XCTAssertEqual(hits.first?.severity, .high)
    }

    func testACEInhibitorPlusPotassiumIsCaution() {
        let hits = InteractionRubric().checkFood([.potassiumRich], against: context(meds: [.aceInhibitor]))
        XCTAssertTrue(hits.contains { $0.severity == .caution })
        XCTAssertFalse(hits.contains { $0.severity == .high })
    }

    func testSeverityOrdering() {
        XCTAssertTrue(InteractionRubric.Severity.info < .caution)
        XCTAssertTrue(InteractionRubric.Severity.caution < .high)
    }

    // MARK: - ResponseBuilder authority + disclaimer

    func testHighHitSurfacesAsAuthoritativeWarningRegardlessOfLLM() {
        let hit = InteractionRubric.Hit(reason: "bleeding risk", severity: .high, basis: "x")
        // Even if the LLM "advisory" wrongly says it's fine, the high warning leads.
        let out = HealthSafetyResponseBuilder.compose(
            subject: "ibuprofen", hits: [hit],
            llmAdvisory: "Ibuprofen is generally safe and fine to take.",
            citations: ["medications"])
        XCTAssertTrue(out.contains("Not recommended"))
        XCTAssertTrue(out.hasPrefix("⚠️"))
        XCTAssertTrue(HealthSafetyResponseBuilder.hasAuthoritativeWarning([hit]))
    }

    func testDisclaimerAlwaysPresent() {
        let none = HealthSafetyResponseBuilder.compose(subject: "vitamin c", hits: [], llmAdvisory: nil, citations: [])
        XCTAssertTrue(none.contains(HealthSafetyResponseBuilder.disclaimer))
        let withHit = HealthSafetyResponseBuilder.compose(
            subject: "ibuprofen",
            hits: [.init(reason: "r", severity: .caution, basis: "b")],
            llmAdvisory: "notes", citations: ["medications"])
        XCTAssertTrue(withHit.contains(HealthSafetyResponseBuilder.disclaimer))
    }

    func testNoHitsStillReportsAndDisclaims() {
        let out = HealthSafetyResponseBuilder.compose(subject: "vitamin c", hits: [], llmAdvisory: nil, citations: [])
        XCTAssertTrue(out.contains("No high-severity interactions"))
        XCTAssertFalse(HealthSafetyResponseBuilder.hasAuthoritativeWarning([]))
    }

    // MARK: - Broader rubric coverage (AB follow-up)

    func testNewDrugClassifications() {
        XCTAssertEqual(SubstanceCatalog.substance(from: "atorvastatin 20mg").classes, [.statin])
        XCTAssertEqual(SubstanceCatalog.substance(from: "sildenafil").classes, [.pde5Inhibitor])
        XCTAssertEqual(SubstanceCatalog.substance(from: "isosorbide mononitrate").classes, [.nitrate])
        XCTAssertEqual(SubstanceCatalog.substance(from: "oxycodone").classes, [.opioid])
        XCTAssertEqual(SubstanceCatalog.substance(from: "Valium (diazepam)").classes, [.benzodiazepine])
        XCTAssertEqual(SubstanceCatalog.substance(from: "methotrexate").classes, [.methotrexate])
        XCTAssertEqual(SubstanceCatalog.substance(from: "lithium carbonate").classes, [.lithium])
    }

    func testMAOIPlusSSRIIsHigh() {
        // Querying an SSRI while on an MAOI (and the reverse) both fire.
        XCTAssertTrue(InteractionRubric().check(SubstanceCatalog.substance(from: "sertraline"), against: context(meds: [.maoi]))
            .contains { $0.severity == .high && $0.basis.contains("serotonin") })
        XCTAssertTrue(InteractionRubric().check(SubstanceCatalog.substance(from: "phenelzine"), against: context(meds: [.ssri]))
            .contains { $0.severity == .high })
    }

    func testPDE5PlusNitrateIsHigh() {
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "sildenafil"), against: context(meds: [.nitrate]))
        XCTAssertEqual(hits.first?.severity, .high)
    }

    func testMethotrexatePlusNSAIDIsHigh() {
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "ibuprofen"), against: context(meds: [.methotrexate]))
        XCTAssertTrue(hits.contains { $0.severity == .high && $0.basis.contains("methotrexate") })
    }

    func testOpioidPlusBenzodiazepineIsHigh() {
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "oxycodone"), against: context(meds: [.benzodiazepine]))
        XCTAssertEqual(hits.first?.severity, .high)
    }

    func testLithiumPlusNSAIDIsHigh() {
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "naproxen"), against: context(meds: [.lithium]))
        XCTAssertTrue(hits.contains { $0.severity == .high && $0.basis.contains("lithium") })
    }

    func testACEPlusPotassiumSparingDiureticIsHigh() {
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "spironolactone"), against: context(meds: [.aceInhibitor]))
        XCTAssertTrue(hits.contains { $0.severity == .high && $0.basis.contains("hyperkalemia") })
    }

    func testNSAIDInPregnancyIsCaution() {
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "ibuprofen"), against: context(meds: [], conditions: [.pregnancy]))
        XCTAssertTrue(hits.contains { $0.severity == .caution && $0.basis.contains("pregnancy") })
    }

    func testAlcoholPlusSedativeIsHigh() {
        let hits = InteractionRubric().checkFood([.alcohol], against: context(meds: [.opioid]))
        XCTAssertEqual(hits.first?.severity, .high)
    }

    func testStatinPlusGrapefruitIsCaution() {
        let hits = InteractionRubric().checkFood([.grapefruit], against: context(meds: [.statin]))
        XCTAssertTrue(hits.contains { $0.severity == .caution && $0.basis.contains("statin") })
    }

    func testUnrelatedNewClassPairingNoHit() {
        // A statin alone with an unrelated query shouldn't fire a high/caution drug-drug rule.
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "vitamin d"), against: context(meds: [.statin]))
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Rubric false negatives (BM P4)

    func testConditionOnlyAnticoagulationPlusNSAIDIsHigh() {
        // "On blood thinners" in conditions.md with no recognised drug name must still
        // fire the flagship NSAID/anticoagulant rule.
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "ibuprofen"),
            against: context(meds: [], conditions: [.anticoagulated]))
        XCTAssertTrue(hits.contains { $0.severity == .high && $0.basis.contains("anticoagulant") })
    }

    func testConditionOnlyAnticoagulationGroundsFromVaultText() {
        // End-to-end through grounding: the condition text alone produces the high hit.
        let g = VaultGrounding()
        let ctx = g.relevantEntries(
            for: HealthSafetyQuery(kind: .canITake, subject: "ibuprofen"),
            medicationsText: "", conditionsText: "- On blood thinners since 2023", allergiesText: "")
        XCTAssertTrue(ctx.conditions.contains(.anticoagulated))
        let hits = InteractionRubric().check(SubstanceCatalog.substance(from: "ibuprofen"), against: ctx)
        XCTAssertTrue(hits.contains { $0.severity == .high })
    }

    func testAnticoagulantMedAndConditionYieldSingleBleedingHit() {
        // Both the drug class and the condition tag present → one hit, not two.
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "naproxen"),
            against: context(meds: [.anticoagulant], conditions: [.anticoagulated]))
        XCTAssertEqual(hits.filter { $0.basis.contains("anticoagulant") }.count, 1)
    }

    func testNSAIDPlusAsthmaIsCaution() {
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "aspirin"),
            against: context(meds: [], conditions: [.asthma]))
        XCTAssertTrue(hits.contains { $0.severity == .caution && $0.basis.contains("asthma") })
    }

    func testNonNSAIDWithAsthmaHasNoHit() {
        let hits = InteractionRubric().check(
            SubstanceCatalog.substance(from: "sertraline"),
            against: context(meds: [], conditions: [.asthma]))
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Unrecognised substances must not get an absence claim (BM P4)

    func testUnrecognizedSubstanceIsNotClassified() {
        XCTAssertFalse(SubstanceCatalog.substance(from: "Zorbifen XR").isClassified)
        XCTAssertTrue(SubstanceCatalog.substance(from: "ibuprofen").isClassified)
    }

    func testUnrecognizedSubjectGetsHonestUncertaintyNotAbsenceClaim() {
        let out = HealthSafetyResponseBuilder.compose(
            subject: "Zorbifen XR", hits: [], subjectRecognized: false,
            llmAdvisory: nil, citations: ["medications"])
        XCTAssertTrue(out.contains("don't recognise"))
        XCTAssertFalse(out.contains("No high-severity interactions"))
        XCTAssertTrue(out.contains(HealthSafetyResponseBuilder.disclaimer))
    }

    func testUnrecognizedSubjectWithAllergyHitStillWarns() {
        // An allergy match fires on the raw name even for an unclassified substance —
        // the warning must win over the "don't recognise" path.
        let hit = InteractionRubric().check(
            SubstanceCatalog.substance(from: "penicillin"),
            against: context(meds: [], allergies: ["penicillin"]))
        let out = HealthSafetyResponseBuilder.compose(
            subject: "penicillin", hits: hit, subjectRecognized: false,
            llmAdvisory: nil, citations: [])
        XCTAssertTrue(out.contains("Not recommended"))
        XCTAssertFalse(out.contains("don't recognise"))
    }

    func testRecognizedSubjectWithNoHitsKeepsAbsenceClaim() {
        let out = HealthSafetyResponseBuilder.compose(
            subject: "atorvastatin", hits: [], subjectRecognized: true,
            llmAdvisory: nil, citations: ["medications"])
        XCTAssertTrue(out.contains("No high-severity interactions"))
        XCTAssertFalse(out.contains("don't recognise"))
    }
}
