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
    /// This measurement's own id, so the records can hold one row per farm's soil and replace
    /// it rather than collecting a row for every save.
    var id = UUID()
    var nitrogen: Double?
    var phosphorus: Double?
    var potassium: Double?
    /// Acidity, 0 to 14.
    var ph: Double?
    var organicCarbonPercent: Double?
    /// What fertilizer has been put on, such as "Urea" or "Compost".
    var fertilizerProduct: String?
    var fertilizerKilogramsPerHectare: Double?
    /// When the helper asked a scientist to look at this soil, if they have. Until then there
    /// is nobody to send the sample to; after it, the helper is waiting on them.
    var scientistAlertedAt: Date?
    /// When these were last saved.
    var updatedAt = Date()

    /// True when nothing has been filled in. The alert does not count: a soil nobody has
    /// measured can still be waiting on a scientist.
    var isEmpty: Bool {
        nitrogen == nil && phosphorus == nil && potassium == nil && ph == nil
            && organicCarbonPercent == nil && fertilizerProduct == nil
            && fertilizerKilogramsPerHectare == nil
    }

    /// True when there is nothing at all to keep, so the farm can go back to having no soil.
    var isUnrecorded: Bool { isEmpty && scientistAlertedAt == nil }

    /// Read so that soil saved before this had an id, or an alert, still loads: a phone that
    /// upgrades keeps what it recorded rather than losing the lot to one missing key.
    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        id = try stored.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nitrogen = try stored.decodeIfPresent(Double.self, forKey: .nitrogen)
        phosphorus = try stored.decodeIfPresent(Double.self, forKey: .phosphorus)
        potassium = try stored.decodeIfPresent(Double.self, forKey: .potassium)
        ph = try stored.decodeIfPresent(Double.self, forKey: .ph)
        organicCarbonPercent = try stored.decodeIfPresent(
            Double.self, forKey: .organicCarbonPercent)
        fertilizerProduct = try stored.decodeIfPresent(String.self, forKey: .fertilizerProduct)
        fertilizerKilogramsPerHectare = try stored.decodeIfPresent(
            Double.self, forKey: .fertilizerKilogramsPerHectare)
        scientistAlertedAt = try stored.decodeIfPresent(Date.self, forKey: .scientistAlertedAt)
        updatedAt = try stored.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    init(
        id: UUID = UUID(), nitrogen: Double? = nil, phosphorus: Double? = nil,
        potassium: Double? = nil, ph: Double? = nil, organicCarbonPercent: Double? = nil,
        fertilizerProduct: String? = nil, fertilizerKilogramsPerHectare: Double? = nil,
        scientistAlertedAt: Date? = nil, updatedAt: Date = Date()
    ) {
        self.id = id
        self.nitrogen = nitrogen
        self.phosphorus = phosphorus
        self.potassium = potassium
        self.ph = ph
        self.organicCarbonPercent = organicCarbonPercent
        self.fertilizerProduct = fertilizerProduct
        self.fertilizerKilogramsPerHectare = fertilizerKilogramsPerHectare
        self.scientistAlertedAt = scientistAlertedAt
        self.updatedAt = updatedAt
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

    /// How the three nutrients read together, from 0 for soil that needs acting on to 1 for
    /// soil that is where it should be. nil until one of them is filled in.
    ///
    /// It is the average of what each nutrient's band means rather than of the numbers
    /// themselves, which cannot be averaged: 120 mg/kg of nitrogen and of potassium are not
    /// the same news. Too much reads as badly as too little, so the bar cannot be gamed by
    /// pouring on fertilizer.
    var npkHealth: Double? {
        let readings = [
            (nitrogen, SoilStandards.nitrogen),
            (phosphorus, SoilStandards.phosphorus),
            (potassium, SoilStandards.potassium),
        ]
        let scores = readings.compactMap { value, standard -> Double? in
            guard let value else { return nil }
            switch standard.note(for: standard.band(for: value))?.tone {
            case .good: return 0.9
            case .watch: return 0.5
            case .act: return 0.1
            case nil: return nil
            }
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// One filled-in value, ready to show.
    struct Row: Identifiable {
        let label: String
        let value: String
        /// Where the value sits against its standard. nil when there is no standard for it.
        let band: SoilBand?
        /// What that band means and what to do. nil with no standard.
        let note: SoilBandNote?
        var id: String { label }
    }

    /// The values that have been filled in, in a fixed order. Empty ones are left out.
    var rows: [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ value: Double?, unit: String, standard: SoilStandard?) {
            guard let value else { return }
            let number = value.formatted(.number.precision(.fractionLength(0...2)))
            let band = standard?.band(for: value)
            rows.append(
                Row(
                    label: label, value: unit.isEmpty ? number : "\(number) \(unit)",
                    band: band, note: band.flatMap { standard?.note(for: $0) }))
        }
        add("Nitrogen (N)", nitrogen, unit: "mg/kg", standard: SoilStandards.nitrogen)
        add("Phosphorus (P)", phosphorus, unit: "mg/kg", standard: SoilStandards.phosphorus)
        add("Potassium (K)", potassium, unit: "mg/kg", standard: SoilStandards.potassium)
        add("pH", ph, unit: "", standard: SoilStandards.ph)
        add(
            "Organic carbon", organicCarbonPercent, unit: "%",
            standard: SoilStandards.organicCarbon)
        if fertilizerProduct != nil || fertilizerKilogramsPerHectare != nil {
            var parts: [String] = []
            if let fertilizerProduct { parts.append(fertilizerProduct) }
            if let amount = fertilizerKilogramsPerHectare {
                parts.append(
                    "\(amount.formatted(.number.precision(.fractionLength(0...2)))) kg/ha")
            }
            // No standard for fertilizer yet, so no band.
            rows.append(
                Row(
                    label: "Fertilizer", value: parts.joined(separator: " · "), band: nil,
                    note: nil))
        }
        return rows
    }
}
