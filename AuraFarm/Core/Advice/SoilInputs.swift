//
//  SoilInputs.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 13/11/26.
//

import Foundation

/// The soil measurements a piece of advice is written with: the five that have a standard.
/// Fertilizer is left out. It has no standard yet, and an amount in the prompt would only
/// tempt the model into quoting a dose.
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
        func add(_ name: String, _ short: String, _ value: Double?, _ unit: String, _ standard: SoilStandard) {
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
            organicCarbonPercent: soil.organicCarbonPercent)
        if isEmpty { return nil }
    }
}
