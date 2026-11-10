//
//  SoilMeasurements.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import Foundation

/// What a field helper knows about a farm's soil apart from the microscope tests. Every part is
/// optional: a helper fills in what they have, and leaves the rest.
///
/// Units are fixed, not chosen by the helper, so a number always means the same thing:
/// nitrogen, phosphorus and potassium in milligrams per kilogram of soil, organic carbon as a
/// percentage of the soil by weight, and fertilizer in kilograms per hectare. They are the units
/// a soil lab report usually gives; if the team reports in others, change them here and in the
/// form together.
struct SoilMeasurements: Codable, Equatable {
    var nitrogen: Double?
    var phosphorus: Double?
    var potassium: Double?
    /// Acidity, 0 to 14.
    var ph: Double?
    var organicCarbonPercent: Double?
    /// What fertilizer has been put on, such as "Urea" or "Compost".
    var fertilizerProduct: String?
    var fertilizerKilogramsPerHectare: Double?
    /// When these were last saved.
    var updatedAt = Date()

    /// True when nothing has been filled in.
    var isEmpty: Bool {
        nitrogen == nil && phosphorus == nil && potassium == nil && ph == nil
            && organicCarbonPercent == nil && fertilizerProduct == nil
            && fertilizerKilogramsPerHectare == nil
    }

    /// What is wrong with the numbers, in words, for the form to show. Empty when all is well.
    var problems: [String] {
        var found: [String] = []
        if let ph, !(0...14).contains(ph) { found.append("pH is between 0 and 14.") }
        if let organicCarbonPercent, !(0...100).contains(organicCarbonPercent) {
            found.append("Organic carbon is a percentage, between 0 and 100.")
        }
        for (name, value) in [
            ("Nitrogen", nitrogen), ("Phosphorus", phosphorus), ("Potassium", potassium),
            ("Fertilizer amount", fertilizerKilogramsPerHectare),
        ] {
            if let value, value < 0 { found.append("\(name) cannot be negative.") }
        }
        return found
    }

    /// One filled-in value, ready to show.
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// The values that have been filled in, in a fixed order. Empty ones are left out.
    var rows: [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ value: Double?, unit: String) {
            guard let value else { return }
            let number = value.formatted(.number.precision(.fractionLength(0...2)))
            rows.append(Row(label: label, value: unit.isEmpty ? number : "\(number) \(unit)"))
        }
        add("Nitrogen (N)", nitrogen, unit: "mg/kg")
        add("Phosphorus (P)", phosphorus, unit: "mg/kg")
        add("Potassium (K)", potassium, unit: "mg/kg")
        add("pH", ph, unit: "")
        add("Organic carbon", organicCarbonPercent, unit: "%")
        if fertilizerProduct != nil || fertilizerKilogramsPerHectare != nil {
            var parts: [String] = []
            if let fertilizerProduct { parts.append(fertilizerProduct) }
            if let amount = fertilizerKilogramsPerHectare {
                parts.append(
                    "\(amount.formatted(.number.precision(.fractionLength(0...2)))) kg/ha")
            }
            rows.append(Row(label: "Fertilizer", value: parts.joined(separator: " · ")))
        }
        return rows
    }
}
