import Foundation

/// The kind of fertilizer put on a field, as far as the field helper knows it. Chosen from a short
/// list, not typed, so the same answer always reads the same.
///
/// The choice is context, never a verdict: neither organic nor inorganic is better by its name.
/// The type alone never leads to a recommendation. Fertilizer advice needs other evidence too,
/// such as a nutrient reading that is low or excessive, or a recent application.
///
/// PLACEHOLDER: the wording is a first reviewed draft that no agronomist has checked.
enum FertilizerType: String, Codable, CaseIterable, Identifiable {
    case organic
    case inorganic
    case blend
    /// The helper does not know which kind it was. Nothing is guessed from this.
    case notSure
    /// The helper chose to say that none was recorded. It is not proof that none was used, and it
    /// is not the same as never having been asked, which is the type being nil.
    case noneRecorded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .organic: return "Organic fertilizer"
        case .inorganic: return "Inorganic fertilizer"
        case .blend: return "Organic–inorganic blend"
        case .notSure: return "Not sure"
        case .noneRecorded: return "No fertilizer recorded"
        }
    }

    /// What the choice means, for the form.
    var definition: String {
        switch self {
        case .organic:
            return
                "Derived mainly from plant, animal, manure, compost, or other biological materials. Nutrients often need microbial breakdown before becoming available, and it may add organic carbon."
        case .inorganic:
            return
                "Manufactured or mineral fertilizer supplying nutrients in more readily available forms. It may provide predictable nutrient amounts, but incorrect use can contribute to nutrient loss, acidification, salinity, or imbalance."
        case .blend:
            return
                "Contains both organic material and mineral or manufactured nutrients. Its effects depend on the composition and application."
        case .notSure:
            return "The field helper does not know the fertilizer category. Nothing is inferred from this."
        case .noneRecorded:
            return
                "No fertilizer information has been entered. This is not proof that no fertilizer was used."
        }
    }

    /// General education about the type. nil for the two choices that say nothing about the
    /// fertilizer itself.
    var education: String? {
        switch self {
        case .organic:
            return
                "Organic fertilizers can release nutrients gradually and may add carbon that supports soil structure and soil organisms. Their nutrient content can vary, and poorly matured or excessive material may create nutrient, salt, oxygen, or disease risks."
        case .inorganic:
            return
                "Inorganic fertilizers can supply specific nutrients in predictable, readily available forms. Too much or poorly timed application can increase nutrient loss, soil acidification, salinity, or nutrient imbalance."
        case .blend:
            return
                "A blend can combine gradual release from organic material with readily available nutrients. How it behaves depends on what is in it and how much is applied."
        case .notSure, .noneRecorded:
            return nil
        }
    }

    /// How the kind sits against what rice paddy research generally favours: organic material,
    /// alone or with mineral fertilizer. Long-term paddy trials, mostly in China, find combined
    /// organic and mineral fertilizer gives steadier yields and more soil carbon than mineral
    /// alone, while mineral alone for many seasons can lower soil carbon and acidify the soil.
    /// nil when the kind says nothing about the fertilizer.
    ///
    /// PLACEHOLDER: a first reading of the research that no agronomist has checked.
    var tone: SoilTone? {
        switch self {
        case .organic, .blend: return .good
        case .inorganic: return .watch
        case .notSure, .noneRecorded: return nil
        }
    }

    /// The word shown beside the kind, as a band is beside a measurement.
    var verdict: String? {
        switch tone {
        case .good: return "Suits paddies"
        case .watch: return "Could improve"
        default: return nil
        }
    }

    /// One line on what this kind does to the soil now. nil when there is nothing to say.
    var effect: String? {
        switch self {
        case .organic:
            return
                "Releases nutrients slowly and adds carbon that feeds soil life, which generally suits paddies. Use composted material, as fresh manure under flooding can raise methane."
        case .blend:
            return
                "Slow organic nutrients with ready mineral ones. Paddy trials often find steadier yields and more soil carbon than mineral fertilizer alone."
        case .inorganic:
            return
                "Feeds the crop quickly but adds no organic carbon. Used alone for many seasons, it can leave paddy soil lower in carbon and more acidic. Moving toward organic fertilizer generally suits paddies better."
        case .notSure, .noneRecorded: return nil
        }
    }

    /// True for the three choices that name a kind of fertilizer.
    var namesAKind: Bool {
        switch self {
        case .organic, .inorganic, .blend: return true
        case .notSure, .noneRecorded: return false
        }
    }

    /// Said once, whatever the type.
    static let sharedNote =
        "The effect depends on the product, amount, timing, soil test, and field conditions."
}
