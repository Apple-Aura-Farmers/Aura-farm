//
//  SoilInputs.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 13/11/26.
//

import Foundation

/// The soil measurements a piece of advice is written with: the five that have a standard, and
/// two things that change how they are read: whether the field was flooded when the pH was
/// measured, and the kind of fertilizer.
///
/// The fertilizer's amount and product name are left out. An amount in the prompt would only
/// tempt the model into quoting a dose, and a product name can be a brand. The kind is kept only
/// when it names one (organic, inorganic or a blend), and only beside at least one reading: on its
/// own it is never advice.
///
/// Two values are the same when their numbers are, whatever day they were saved. Saving the
/// form again without changing anything is not a change, so it does not rewrite the advice.
///
/// PLACEHOLDER: the bands come from `SoilStandards`, which no agronomist has checked.
struct SoilInputs: Codable, Equatable, Hashable {
    var nitrogen: Double?
    var phosphorus: Double?
    var potassium: Double?
    var ph: Double?
    var organicCarbonPercent: Double?
    /// Only kept when there is a pH reading.
    var phFieldWater: PHFieldWater?
    /// Only kept when it names a kind of fertilizer.
    var fertilizerType: FertilizerType?

    /// True when there is no reading. The two notes above are not readings.
    var isEmpty: Bool {
        nitrogen == nil && phosphorus == nil && potassium == nil && ph == nil
            && organicCarbonPercent == nil
    }

    /// One filled-in measurement, with where it sits against its standard.
    struct Reading: Equatable {
        /// How the prompt and the update note name it, for example "nitrogen".
        let name: String
        /// The short form for the "Based on" line, for example "N".
        let short: String
        let value: Double
        /// Empty for pH, which has none.
        let unit: String
        let band: SoilBand
    }

    /// The filled-in measurements, in a fixed order.
    var readings: [Reading] {
        var readings: [Reading] = []
        func add(_ name: String, _ short: String, _ value: Double?, _ unit: String, _ standard: SoilStandard)
        {
            guard let value else { return }
            readings.append(
                Reading(
                    name: name, short: short, value: value, unit: unit, band: standard.band(for: value)))
        }
        add("nitrogen", "N", nitrogen, "mg/kg", SoilStandards.nitrogen)
        add("phosphorus", "P", phosphorus, "mg/kg", SoilStandards.phosphorus)
        add("potassium", "K", potassium, "mg/kg", SoilStandards.potassium)
        add("pH", "pH", ph, "", SoilStandards.ph)
        add("organic carbon", "organic carbon", organicCarbonPercent, "%", SoilStandards.organicCarbon)
        return readings
    }
}

extension SoilInputs {
    /// What the advice can read from a farm's soil measurements. nil when nothing it can read
    /// has been filled in, so a farm with no measurements and one with only a fertilizer note
    /// are the same to the advice.
    init?(_ soil: SoilMeasurements?) {
        guard let soil else { return nil }
        self.init(
            nitrogen: soil.nitrogen, phosphorus: soil.phosphorus, potassium: soil.potassium, ph: soil.ph,
            organicCarbonPercent: soil.organicCarbonPercent,
            phFieldWater: soil.ph == nil ? nil : soil.phFieldWater,
            fertilizerType: soil.fertilizerType?.namesAKind == true ? soil.fertilizerType : nil)
        if isEmpty { return nil }
    }
}
