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
    /// How the pH was measured. No longer asked for or shown, and nothing reads it; kept so saved
    /// farms and exported reports that have it still load.
    var phMethod: PHMethod?
    /// Whether the field was flooded when the pH was measured. nil when the helper did not say.
    var phFieldWater: PHFieldWater?
    /// The kind of fertilizer, chosen from a fixed list. nil when the question was never answered,
    /// which is not the same as `.noneRecorded`.
    var fertilizerType: FertilizerType?
    /// The product's name, if the helper knows it. Shown on the farm's page and in the report, and
    /// never sent to Apple Intelligence, because a product name can be a brand.
    var fertilizerProduct: String?
    /// Shown on the farm's page and in the report, and never sent to Apple Intelligence, so the
    /// model is never tempted to repeat it as a dose.
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
            && organicCarbonPercent == nil && phMethod == nil && phFieldWater == nil
            && fertilizerType == nil && fertilizerProduct == nil && fertilizerKilogramsPerHectare == nil
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
        phMethod = try stored.decodeIfPresent(PHMethod.self, forKey: .phMethod)
        phFieldWater = try stored.decodeIfPresent(PHFieldWater.self, forKey: .phFieldWater)
        fertilizerType = try stored.decodeIfPresent(FertilizerType.self, forKey: .fertilizerType)
        fertilizerProduct = try stored.decodeIfPresent(String.self, forKey: .fertilizerProduct)
        fertilizerKilogramsPerHectare = try stored.decodeIfPresent(
            Double.self, forKey: .fertilizerKilogramsPerHectare)
        scientistAlertedAt = try stored.decodeIfPresent(Date.self, forKey: .scientistAlertedAt)
        updatedAt = try stored.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    init(
        id: UUID = UUID(), nitrogen: Double? = nil, phosphorus: Double? = nil,
        potassium: Double? = nil, ph: Double? = nil, organicCarbonPercent: Double? = nil,
        phMethod: PHMethod? = nil, phFieldWater: PHFieldWater? = nil,
        fertilizerType: FertilizerType? = nil,
        fertilizerProduct: String? = nil, fertilizerKilogramsPerHectare: Double? = nil,
        scientistAlertedAt: Date? = nil, updatedAt: Date = Date()
    ) {
        self.id = id
        self.nitrogen = nitrogen
        self.phosphorus = phosphorus
        self.potassium = potassium
        self.ph = ph
        self.organicCarbonPercent = organicCarbonPercent
        self.phMethod = phMethod
        self.phFieldWater = phFieldWater
        self.fertilizerType = fertilizerType
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
        /// What the measurement does and what this reading may mean. nil with no standard.
        var education: SoilEducation.Detail? = nil
        /// A line under the value, such as how the pH was measured.
        var context: String? = nil
        /// Set on the fertilizer row only.
        var fertilizerType: FertilizerType? = nil
        /// The reading and its standard, for drawing where it sits. nil with no standard.
        var number: Double? = nil
        var standard: SoilStandard? = nil
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
                    band: band, note: band.flatMap { standard?.note(for: $0) },
                    education: band.flatMap { standard?.education.detail(for: $0) },
                    context: label == "pH" ? phContext : nil, number: value, standard: standard))
        }
        add("Nitrogen (N)", nitrogen, unit: "mg/kg", standard: SoilStandards.nitrogen)
        add("Phosphorus (P)", phosphorus, unit: "mg/kg", standard: SoilStandards.phosphorus)
        add("Potassium (K)", potassium, unit: "mg/kg", standard: SoilStandards.potassium)
        add("pH", ph, unit: "", standard: SoilStandards.ph)
        add(
            "Organic carbon", organicCarbonPercent, unit: "%",
            standard: SoilStandards.organicCarbon)
        if let fertilizer = fertilizerSummary {
            // No standard for fertilizer, so no band. It is context, not a reading.
            rows.append(
                Row(
                    label: "Fertilizer", value: fertilizer, band: nil, note: nil, education: nil,
                    context: nil, fertilizerType: fertilizerType))
        }
        return rows
    }

    /// "Drained when measured". nil when not recorded.
    var phContext: String? { phFieldWater?.label }

    /// "Organic fertilizer · Compost · 50 kg/ha", from whatever was recorded. nil when nothing was.
    var fertilizerSummary: String? {
        var parts: [String] = []
        if let fertilizerType { parts.append(fertilizerType.label) }
        if let fertilizerProduct { parts.append(fertilizerProduct) }
        if let amount = fertilizerKilogramsPerHectare {
            parts.append("\(amount.formatted(.number.precision(.fractionLength(0...2)))) kg/ha")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// How a pH reading was taken. A lab reading of dried soil and a probe in a flooded field can
/// differ, so the app keeps how it was taken beside the number.
enum PHMethod: String, Codable, CaseIterable, Identifiable {
    case laboratory
    case fieldProbe
    case notSure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .laboratory: return "Laboratory test"
        case .fieldProbe: return "Field probe or kit"
        case .notSure: return "Method not known"
        }
    }
}

/// Whether the field had standing water when the pH was measured. Flooding moves acidic and
/// alkaline soils toward neutral, so a reading from dry soil may not be the pH around the roots
/// once the field is flooded.
enum PHFieldWater: String, Codable, CaseIterable, Identifiable {
    case flooded
    case drained
    case notSure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flooded: return "Flooded when measured"
        case .drained: return "Drained or dry when measured"
        case .notSure: return "Water not known"
        }
    }
}
