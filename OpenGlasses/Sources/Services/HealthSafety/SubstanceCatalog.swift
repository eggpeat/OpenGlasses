import Foundation

/// Drug classes the interaction rubric reasons over (Plan AB). Deliberately a small,
/// curated set covering the well-established high-severity interactions — not a
/// pharmacological taxonomy.
enum DrugClass: String, CaseIterable, Equatable {
    case nsaid                 // ibuprofen, naproxen, aspirin, diclofenac
    case anticoagulant         // warfarin, apixaban, rivaroxaban, dabigatran
    case aceInhibitor          // lisinopril, enalapril, ramipril
    case arb                   // losartan, valsartan
    case maoi                  // phenelzine, tranylcypromine, isocarboxazid
    case potassiumSparingDiuretic // spironolactone, amiloride
    case ssri                  // sertraline, fluoxetine
    case statin                // atorvastatin, simvastatin, rosuvastatin
    case nitrate               // nitroglycerin, isosorbide
    case pde5Inhibitor         // sildenafil, tadalafil
    case benzodiazepine        // diazepam, alprazolam, lorazepam
    case opioid                // oxycodone, morphine, tramadol, fentanyl
    case methotrexate          // methotrexate (its own class — narrow therapeutic index)
    case lithium               // lithium (narrow therapeutic index)
}

/// Tags for foods/labels the rubric checks against meds + conditions (Plan AB).
enum FoodTag: String, CaseIterable, Equatable {
    case tyramineRich          // aged cheese, cured meat, soy sauce — MAOI crisis
    case vitaminKRich          // leafy greens — warfarin antagonism
    case potassiumRich         // banana, salt substitute — ACE/ARB + K hyperkalemia
    case highSodium            // hypertension / heart failure
    case purineRich            // organ meat, shellfish — gout
    case grapefruit            // CYP3A4 interactions
    case alcohol               // additive CNS/respiratory depression with sedatives
}

/// Conditions the rubric uses for contraindications (Plan AB).
enum ConditionTag: String, CaseIterable, Equatable {
    case pepticUlcer
    case kidneyDisease         // CKD
    case anticoagulated        // on blood thinners (also derivable from meds)
    case hypertension
    case gout
    case asthma
    case pregnancy
}

/// A substance normalised for rubric reasoning: its raw name plus any drug classes
/// it belongs to (Plan AB). Pure value type.
struct Substance: Equatable {
    let raw: String
    let classes: Set<DrugClass>

    var isClassified: Bool { !classes.isEmpty }
}

/// Pure synonym tables mapping free text (vault lines, a spoken substance, a food
/// label) to the rubric's drug classes / food tags / conditions. Curated, not
/// exhaustive — the LLM long-tail covers the rest.
enum SubstanceCatalog {

    /// name fragment → drug class. Matched as a word/substring of lowercased text.
    static let drugSynonyms: [String: DrugClass] = [
        "ibuprofen": .nsaid, "advil": .nsaid, "motrin": .nsaid, "naproxen": .nsaid,
        "aleve": .nsaid, "aspirin": .nsaid, "diclofenac": .nsaid, "celecoxib": .nsaid, "nsaid": .nsaid,
        "warfarin": .anticoagulant, "coumadin": .anticoagulant, "apixaban": .anticoagulant,
        "eliquis": .anticoagulant, "rivaroxaban": .anticoagulant, "xarelto": .anticoagulant,
        "dabigatran": .anticoagulant, "heparin": .anticoagulant,
        "lisinopril": .aceInhibitor, "enalapril": .aceInhibitor, "ramipril": .aceInhibitor,
        "perindopril": .aceInhibitor,
        "losartan": .arb, "valsartan": .arb, "candesartan": .arb,
        "phenelzine": .maoi, "nardil": .maoi, "tranylcypromine": .maoi, "isocarboxazid": .maoi,
        "selegiline": .maoi,
        "spironolactone": .potassiumSparingDiuretic, "amiloride": .potassiumSparingDiuretic,
        "sertraline": .ssri, "zoloft": .ssri, "fluoxetine": .ssri, "prozac": .ssri,
        "citalopram": .ssri, "escitalopram": .ssri,
        "atorvastatin": .statin, "lipitor": .statin, "simvastatin": .statin, "zocor": .statin,
        "rosuvastatin": .statin, "crestor": .statin, "pravastatin": .statin,
        "nitroglycerin": .nitrate, "nitroglycerine": .nitrate, "isosorbide": .nitrate, "nitrate": .nitrate,
        "sildenafil": .pde5Inhibitor, "viagra": .pde5Inhibitor, "tadalafil": .pde5Inhibitor,
        "cialis": .pde5Inhibitor, "vardenafil": .pde5Inhibitor,
        "diazepam": .benzodiazepine, "valium": .benzodiazepine, "alprazolam": .benzodiazepine,
        "xanax": .benzodiazepine, "lorazepam": .benzodiazepine, "ativan": .benzodiazepine,
        "clonazepam": .benzodiazepine, "klonopin": .benzodiazepine,
        "oxycodone": .opioid, "oxycontin": .opioid, "hydrocodone": .opioid, "morphine": .opioid,
        "codeine": .opioid, "tramadol": .opioid, "fentanyl": .opioid, "oxymorphone": .opioid,
        "methotrexate": .methotrexate,
        "lithium": .lithium,
    ]

    /// food/label fragment → tag.
    static let foodSynonyms: [String: FoodTag] = [
        "aged cheese": .tyramineRich, "cheddar": .tyramineRich, "blue cheese": .tyramineRich,
        "cured": .tyramineRich, "salami": .tyramineRich, "soy sauce": .tyramineRich,
        "sauerkraut": .tyramineRich, "tofu": .tyramineRich, "miso": .tyramineRich,
        "spinach": .vitaminKRich, "kale": .vitaminKRich, "broccoli": .vitaminKRich,
        "collard": .vitaminKRich, "brussels": .vitaminKRich,
        "banana": .potassiumRich, "salt substitute": .potassiumRich, "potassium": .potassiumRich,
        "orange juice": .potassiumRich, "avocado": .potassiumRich,
        "sodium": .highSodium, "salt": .highSodium,
        "liver": .purineRich, "anchovies": .purineRich, "shellfish": .purineRich, "sardines": .purineRich,
        "grapefruit": .grapefruit,
        "alcohol": .alcohol, "beer": .alcohol, "wine": .alcohol, "whiskey": .alcohol,
        "vodka": .alcohol, "liquor": .alcohol, "spirits": .alcohol, "cocktail": .alcohol,
    ]

    /// condition fragment → tag (matched in the conditions vault file).
    static let conditionSynonyms: [String: ConditionTag] = [
        "peptic ulcer": .pepticUlcer, "stomach ulcer": .pepticUlcer, "gastric ulcer": .pepticUlcer,
        "ckd": .kidneyDisease, "kidney disease": .kidneyDisease, "renal": .kidneyDisease,
        "kidney failure": .kidneyDisease,
        "anticoagulat": .anticoagulated, "blood thinner": .anticoagulated,
        "hypertension": .hypertension, "high blood pressure": .hypertension,
        "gout": .gout,
        "asthma": .asthma,
        "pregnan": .pregnancy,
    ]

    /// Classify a free-text substance name into a `Substance` (its drug classes).
    static func substance(from text: String) -> Substance {
        let lower = text.lowercased()
        let classes = Set(drugSynonyms.compactMap { lower.contains($0.key) ? $0.value : nil })
        return Substance(raw: text.trimmingCharacters(in: .whitespacesAndNewlines), classes: classes)
    }

    /// Food tags present in a free-text food/label string.
    static func foodTags(in text: String) -> Set<FoodTag> {
        let lower = text.lowercased()
        return Set(foodSynonyms.compactMap { lower.contains($0.key) ? $0.value : nil })
    }

    /// Condition tags present in free-text conditions content.
    static func conditionTags(in text: String) -> Set<ConditionTag> {
        let lower = text.lowercased()
        return Set(conditionSynonyms.compactMap { lower.contains($0.key) ? $0.value : nil })
    }
}
