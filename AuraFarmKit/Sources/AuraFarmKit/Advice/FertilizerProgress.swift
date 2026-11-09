import Foundation

/// What a farmer can record putting on a field. Wider than `Fertilizer`, because farmers also
/// use compound NPK (such as Phonska) and organic matter, which the plan does not dose.
public enum AppliedProduct: String, CaseIterable, Codable, Sendable {
    case urea
    case sp36
    case kcl
    /// A compound NPK fertilizer, such as Phonska 15-15-15.
    case npkCompound
    /// Compost, manure or straw compost.
    case organic
    case other

    public var label: String {
        switch self {
        case .urea: return "Urea"
        case .sp36: return "SP-36"
        case .kcl: return "KCl"
        case .npkCompound: return "NPK compound (e.g. Phonska)"
        case .organic: return "Compost or manure"
        case .other: return "Other"
        }
    }

    /// The planned fertilizer this counts towards, or nil when the plan does not cover it.
    public var plannedFertilizer: Fertilizer? {
        switch self {
        case .urea: return .urea
        case .sp36: return .sp36
        case .kcl: return .kcl
        case .npkCompound, .organic, .other: return nil
        }
    }
}

/// How much of one planned fertilizer has gone on this season.
public struct FertilizerProgress: Equatable, Sendable {
    public var fertilizer: Fertilizer
    /// The plan's dose for the whole field, or nil when the field's area is not known.
    public var plannedKilograms: Double?
    public var appliedKilograms: Double

    public init(fertilizer: Fertilizer, plannedKilograms: Double?, appliedKilograms: Double) {
        self.fertilizer = fertilizer
        self.plannedKilograms = plannedKilograms
        self.appliedKilograms = appliedKilograms
    }

    /// Applied as a share of planned, or nil without a plan for the field.
    public var shareApplied: Double? {
        guard let plannedKilograms, plannedKilograms > 0 else { return nil }
        return appliedKilograms / plannedKilograms
    }

    /// One entry per fertilizer in the plan, in the plan's order. Compound NPK, organic
    /// matter and other products are left out: their nutrients cannot be read off a label
    /// this app knows.
    public static func compare(
        doses: [FertilizerDose],
        applied: [(product: AppliedProduct, kilograms: Double)]
    ) -> [FertilizerProgress] {
        doses.map { dose in
            let total = applied
                .filter { $0.product.plannedFertilizer == dose.fertilizer }
                .reduce(0) { $0 + $1.kilograms }
            return FertilizerProgress(
                fertilizer: dose.fertilizer,
                plannedKilograms: dose.kilogramsForField,
                appliedKilograms: total
            )
        }
    }
}

/// Harvest yield, kept in one unit.
public enum HarvestYield {
    /// Tonnes a hectare from a field's total harvest in kilograms. nil without a usable area.
    public static func tonnesPerHectare(totalKilograms: Double, areaHectares: Double?) -> Double? {
        guard let areaHectares, areaHectares > 0, totalKilograms >= 0 else { return nil }
        return totalKilograms / 1_000 / areaHectares
    }

    /// The yield the national doses are written for, in tonnes a hectare of unhusked rice.
    public static let guideRangeTonnesPerHectare = 5.0...7.0
}
