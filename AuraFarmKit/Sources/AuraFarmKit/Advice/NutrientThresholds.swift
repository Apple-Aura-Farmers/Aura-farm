import Foundation

/// The units a lab reports N, P and K in that this app knows how to class.
///
/// A value in any other unit is kept as entered, and the class is picked by hand from what the
/// lab report says.
public enum NutrientUnit: String, CaseIterable, Codable, Sendable {
    /// Total nitrogen, percent of dry soil (Kjeldahl).
    case totalNitrogenPercent
    /// Potential phosphorus, mg P₂O₅ per 100 g soil, extracted with 25% HCl.
    case phosphatePerHundredGramsHCl
    /// Potential potassium, mg K₂O per 100 g soil, extracted with 25% HCl.
    case potashPerHundredGramsHCl
    /// Any other unit or extraction, such as Bray or Olsen P in ppm.
    case other

    public var label: String {
        switch self {
        case .totalNitrogenPercent: return "% total N"
        case .phosphatePerHundredGramsHCl: return "mg P₂O₅ / 100 g (HCl 25%)"
        case .potashPerHundredGramsHCl: return "mg K₂O / 100 g (HCl 25%)"
        case .other: return "Other unit"
        }
    }

    /// The units that can be entered for a nutrient, the one with thresholds first.
    public static func units(for nutrient: Nutrient) -> [NutrientUnit] {
        switch nutrient {
        case .nitrogen: return [.totalNitrogenPercent, .other]
        case .phosphorus: return [.phosphatePerHundredGramsHCl, .other]
        case .potassium: return [.potashPerHundredGramsHCl, .other]
        }
    }
}

/// Where a lab value stops being low and starts being high, per unit.
///
/// Thresholds are data, not magic numbers. None of them is calibrated by this team.
public struct NutrientThresholds: Equatable, Sendable {
    /// Below this the nutrient is low.
    public var lowBelow: Double
    /// Above this the nutrient is high. Between the two it is medium.
    public var highAbove: Double

    public init(lowBelow: Double, highAbove: Double) {
        self.lowBelow = lowBelow
        self.highAbove = highAbove
    }

    public func level(of value: Double) -> NutrientLevel {
        if value < lowBelow { return .low }
        if value > highAbove { return .high }
        return .medium
    }

    /// The thresholds for a unit, or nil for a unit this app cannot class.
    ///
    /// - P and K, HCl 25%: low below 20 and 10, high above 40 and 20 mg per 100 g. The classes
    ///   behind the national paddy P and K recommendation (Sofyan and Suryono 2002, used in
    ///   Permentan 40/2007). Not calibrated by this team.
    /// - Total N: low below 0.21%, high above 0.50%. The Balai Penelitian Tanah lab criteria,
    ///   folding "very low" into low and "very high" into high. Not calibrated by this team, and
    ///   still to be checked against the published table before a field visit relies on it.
    public static func forUnit(_ unit: NutrientUnit) -> NutrientThresholds? {
        switch unit {
        case .totalNitrogenPercent: return NutrientThresholds(lowBelow: 0.21, highAbove: 0.50)
        case .phosphatePerHundredGramsHCl: return NutrientThresholds(lowBelow: 20, highAbove: 40)
        case .potashPerHundredGramsHCl: return NutrientThresholds(lowBelow: 10, highAbove: 20)
        case .other: return nil
        }
    }

    /// The class for a lab value, or nil when the unit has no thresholds here.
    public static func level(of value: Double, in unit: NutrientUnit) -> NutrientLevel? {
        forUnit(unit)?.level(of: value)
    }
}
