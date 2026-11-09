import AuraFarmKit
import Foundation
import SwiftData

/// N, P and K results for a field, typed in by hand from a soil test kit or a lab report.
///
/// Kept apart from `SoilTest`: NPK comes from a different test, on a different day, and never
/// arrives in an `.aurafarm` report.
@Model
final class NutrientTest {
    var testedAt: Date
    var createdAt: Date
    /// A `NutrientSource` raw value. Kept as text so a value a newer build adds still loads.
    var sourceRaw: String
    /// The kit or lab, for example "PUTS" or the lab's name.
    var sourceName: String = ""

    /// `NutrientLevel` raw values. nil when that nutrient was not tested.
    var nitrogenLevelRaw: String? = nil
    var phosphorusLevelRaw: String? = nil
    var potassiumLevelRaw: String? = nil

    /// The lab value as reported, when there is one. The level above is what the advice uses.
    var nitrogenValue: Double? = nil
    var phosphorusValue: Double? = nil
    var potassiumValue: Double? = nil
    /// `NutrientUnit` raw values for the lab values.
    var nitrogenUnitRaw: String? = nil
    var phosphorusUnitRaw: String? = nil
    var potassiumUnitRaw: String? = nil

    /// pH in water. nil when it was not measured.
    var pH: Double? = nil
    /// A `StrawPractice` raw value: what happened to the straw after the last harvest.
    var strawRaw: String = StrawPractice.unknown.rawValue
    var notes: String = ""
    var field: Field? = nil

    init(testedAt: Date, source: NutrientSource, createdAt: Date = .now) {
        self.testedAt = testedAt
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
    }

    var source: NutrientSource {
        get { NutrientSource(rawValue: sourceRaw) ?? .soilTestKit }
        set { sourceRaw = newValue.rawValue }
    }

    var straw: StrawPractice {
        get { StrawPractice(rawValue: strawRaw) ?? .unknown }
        set { strawRaw = newValue.rawValue }
    }

    func level(of nutrient: Nutrient) -> NutrientLevel? {
        levelRaw(of: nutrient).flatMap(NutrientLevel.init(rawValue:))
    }

    func setLevel(_ level: NutrientLevel?, of nutrient: Nutrient) {
        switch nutrient {
        case .nitrogen: nitrogenLevelRaw = level?.rawValue
        case .phosphorus: phosphorusLevelRaw = level?.rawValue
        case .potassium: potassiumLevelRaw = level?.rawValue
        }
    }

    /// The lab value and its unit, when one was entered.
    func measurement(of nutrient: Nutrient) -> (value: Double, unit: NutrientUnit)? {
        let stored: (value: Double?, unitRaw: String?) =
            switch nutrient {
            case .nitrogen: (nitrogenValue, nitrogenUnitRaw)
            case .phosphorus: (phosphorusValue, phosphorusUnitRaw)
            case .potassium: (potassiumValue, potassiumUnitRaw)
            }
        guard let value = stored.value else { return nil }
        return (value, stored.unitRaw.flatMap(NutrientUnit.init(rawValue:)) ?? .other)
    }

    /// Sets or clears the lab value. Pass nil to clear it.
    func setMeasurement(_ measurement: (value: Double, unit: NutrientUnit)?, of nutrient: Nutrient) {
        switch nutrient {
        case .nitrogen:
            nitrogenValue = measurement?.value
            nitrogenUnitRaw = measurement?.unit.rawValue
        case .phosphorus:
            phosphorusValue = measurement?.value
            phosphorusUnitRaw = measurement?.unit.rawValue
        case .potassium:
            potassiumValue = measurement?.value
            potassiumUnitRaw = measurement?.unit.rawValue
        }
    }

    /// The results as the advisor reads them.
    var result: NutrientResult {
        var levels: [Nutrient: NutrientLevel] = [:]
        for nutrient in Nutrient.allCases {
            levels[nutrient] = level(of: nutrient)
        }
        return NutrientResult(testedAt: testedAt, source: source, levels: levels, pH: pH, straw: straw)
    }

    private func levelRaw(of nutrient: Nutrient) -> String? {
        switch nutrient {
        case .nitrogen: return nitrogenLevelRaw
        case .phosphorus: return phosphorusLevelRaw
        case .potassium: return potassiumLevelRaw
        }
    }
}
