import Foundation

/// The single-nutrient fertilizers the national paddy recommendation is written in.
public enum Fertilizer: String, CaseIterable, Codable, Sendable {
    case urea
    case sp36
    case kcl

    /// "Urea", "SP-36" or "KCl", as on the sack.
    public var name: String {
        switch self {
        case .urea: return "Urea"
        case .sp36: return "SP-36"
        case .kcl: return "KCl"
        }
    }

    /// The nutrient the fertilizer is applied for.
    public var nutrient: Nutrient {
        switch self {
        case .urea: return .nitrogen
        case .sp36: return .phosphorus
        case .kcl: return .potassium
        }
    }

    public static func forNutrient(_ nutrient: Nutrient) -> Fertilizer {
        switch nutrient {
        case .nitrogen: return .urea
        case .phosphorus: return .sp36
        case .potassium: return .kcl
        }
    }
}

/// Fertilizer doses per hectare by soil test class, for irrigated rice.
///
/// Doses are data, not magic numbers. They are the published recommendation, not calibrated by
/// this team, and are written for irrigated paddy yielding about 5 to 7 t/ha of unhusked rice
/// (IR-64 or similar). They are a starting point a field helper can explain, not a prescription.
public enum PaddyFertilizerGuide {
    /// What the doses are based on, in words a field helper can repeat.
    public static let basis =
        "Doses follow the national paddy soil test guide (PUTS) for irrigated rice yielding about "
        + "5 to 7 tonnes a hectare."

    /// Urea, kg/ha, by soil N class: 300, 250, 200. PUTS recommendation as reported in Jurnal
    /// Agrikultura 35(1), 2024. Later doses are meant to be adjusted with the leaf colour chart.
    public static func ureaKilogramsPerHectare(nitrogen: NutrientLevel) -> Double {
        switch nitrogen {
        case .low: return 300
        case .medium: return 250
        case .high: return 200
        }
    }

    /// SP-36, kg/ha, by soil P class: 100, 75, 50. Balai Penelitian Tanah recommendation since
    /// 2003 and the PUTS guide.
    public static func sp36KilogramsPerHectare(phosphorus: NutrientLevel) -> Double {
        switch phosphorus {
        case .low: return 100
        case .medium: return 75
        case .high: return 50
        }
    }

    /// KCl, kg/ha, by soil K class and what happened to the straw.
    ///
    /// Low or medium K: 100, or 50 when the straw went back into the field (Balai Penelitian
    /// Tanah). High K: 50 (PUTS, as applied by BSIP Papua). No lower high-K dose for returned
    /// straw is used here, because none was found in a source. Unknown straw is treated as
    /// removed, the larger dose, so the crop is not left short.
    public static func kclKilogramsPerHectare(potassium: NutrientLevel, straw: StrawPractice) -> Double {
        switch potassium {
        case .low, .medium: return straw == .returned ? 50 : 100
        case .high: return 50
        }
    }

    /// The dose of a fertilizer for a soil class.
    public static func kilogramsPerHectare(
        of fertilizer: Fertilizer,
        level: NutrientLevel,
        straw: StrawPractice
    ) -> Double {
        switch fertilizer {
        case .urea: return ureaKilogramsPerHectare(nitrogen: level)
        case .sp36: return sp36KilogramsPerHectare(phosphorus: level)
        case .kcl: return kclKilogramsPerHectare(potassium: level, straw: straw)
        }
    }

    /// Days after transplanting to put each part of the dose on: urea at 3, 30 and 50, SP-36
    /// at 3, KCl at 3 and 30. The same West Sumatra schedule as `schedule(for:)`. Not
    /// calibrated by this team.
    public static func applicationDays(for fertilizer: Fertilizer) -> [Int] {
        switch fertilizer {
        case .urea: return [3, 30, 50]
        case .sp36: return [3]
        case .kcl: return [3, 30]
        }
    }

    /// Below this percentage of organic carbon (C-organik) the soil is low in organic matter.
    /// The 2% line used in Indonesian paddy soil surveys (as in the Malinau site-specific study).
    /// Not calibrated by this team.
    public static let lowOrganicCarbonPercent = 2.0

    /// The organic matter put on in Indonesian paddy trials: 2 t/ha with the Permentan doses,
    /// 5 t/ha of manure or straw compost in West Sumatra. A range to discuss, not a dose.
    public static let organicMatterTonnesPerHectare = 2...5

    /// When to put the fertilizer on, in days after transplanting.
    ///
    /// A common split for irrigated paddy (urea at about 3, 30 and 50 days, all SP-36 at the
    /// start, KCl half and half), as used in West Sumatra site-specific trials. Not calibrated
    /// by this team.
    public static func schedule(for fertilizer: Fertilizer) -> String {
        switch fertilizer {
        case .urea:
            return "Split in three: some in the first few days after transplanting, more at about "
                + "30 days, the rest at about 50 days. Check the leaf colour chart before the later doses."
        case .sp36:
            return "All of it in the first few days after transplanting."
        case .kcl:
            return "Half in the first few days after transplanting, half at about 30 days."
        }
    }
}
