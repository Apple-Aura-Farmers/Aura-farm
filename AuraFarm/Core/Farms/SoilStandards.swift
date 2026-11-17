//
//  SoilStandards.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 11/11/26.
//

import Foundation

/// Where a measurement sits against its standard.
enum SoilBand: Hashable {
    case low
    case standard
    case high
    case excessive

    var label: String {
        switch self {
        case .low: return "Low"
        case .standard: return "Standard"
        case .high: return "High"
        case .excessive: return "Excessive"
        }
    }
}

/// How a band should be read. A high potassium reading is good news and a high pH is not, so
/// the colour and icon follow this and not the band's name.
enum SoilTone {
    case good
    case watch
    case act
}

/// What a band means and what to do about it.
struct SoilBandNote {
    let tone: SoilTone
    /// What the reading may mean. nil when there is nothing to add.
    let effect: String?
    let action: String
}

/// The range a measurement should sit in, and what each band around it means.
///
/// Below `lower` is low. From `lower` to `upper` is standard. Above that to `highUpper` is
/// high, and above `highUpper` is excessive. Each upper edge counts as inside its band.
struct SoilStandard: Equatable {
    let lower: Double
    let upper: Double
    /// The top of the high band. nil when there is no excessive band.
    let highUpper: Double?
    let education: SoilEducation

    func band(for value: Double) -> SoilBand {
        if value < lower { return .low }
        if value <= upper { return .standard }
        if let highUpper, value > highUpper { return .excessive }
        return .high
    }

    /// What a reading in the band may mean and what might be done, as one note.
    func note(for band: SoilBand) -> SoilBandNote? { education.notes[band] }

    /// "80–120". The unit is left to the caller.
    var description: String {
        func text(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...2)))
        }
        return "\(text(lower))–\(text(upper))"
    }
}

/// The standard for each measurement. All the limits live here, and the wording lives in
/// `SoilEducation`, so changing either is a change to one place.
///
/// PROVISIONAL. The ranges are a first draft for flooded rice paddies. No agronomist has checked
/// them. They do not allow for flooded and drained soil differing, for crop stage, or for a probe
/// reading against a lab one, and they leave no margin for a device's accuracy. Replace them
/// before they are relied on. The app says so wherever it shows them.
///
/// The pH range is a provisional flooded-rice target of about 6.0 to 7.0, not a range for every
/// crop and not a perfect one. See `SoilEducation.phCaveat`. The high band to 7.8 is a caution
/// zone, not a diagnosis. The gaps the source left (pH 5.5 to 6.0, potassium 100 to 120, organic
/// carbon 1.5 to 2.0) go to the band below, which is the more cautious reading.
///
/// Fertilizer has no standard. It is context only.
enum SoilStandards {
    /// Nitrogen, in mg/kg.
    static let nitrogen = SoilStandard(lower: 80, upper: 120, highUpper: 150, education: .nitrogen)
    /// Phosphorus, in mg/kg.
    static let phosphorus = SoilStandard(lower: 15, upper: 25, highUpper: 45, education: .phosphorus)
    /// Potassium, in mg/kg.
    static let potassium = SoilStandard(
        lower: 120, upper: 180, highUpper: 280, education: .potassium)
    /// Provisional flooded-rice target of about 6.0 to 7.0.
    static let ph = SoilStandard(lower: 6.0, upper: 7.0, highUpper: 7.8, education: .ph)
    /// Soil organic carbon, as a percentage.
    static let organicCarbon = SoilStandard(
        lower: 2.0, upper: 3.5, highUpper: 6.0, education: .organicCarbon)
}
