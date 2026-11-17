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
    /// What the soil is likely doing. nil when there is nothing to add.
    let effect: String?
    let action: String
}

/// The range a measurement should sit in, and what each band around it means.
///
/// Below `lower` is low. From `lower` to `upper` is standard. Above that to `highUpper` is
/// high, and above `highUpper` is excessive. Each upper edge counts as inside its band.
struct SoilStandard {
    let lower: Double
    let upper: Double
    /// The top of the high band. nil when there is no excessive band.
    let highUpper: Double?
    let notes: [SoilBand: SoilBandNote]

    func band(for value: Double) -> SoilBand {
        if value < lower { return .low }
        if value <= upper { return .standard }
        if let highUpper, value > highUpper { return .excessive }
        return .high
    }

    func note(for band: SoilBand) -> SoilBandNote? { notes[band] }

    /// "80–120". The unit is left to the caller.
    var description: String {
        func text(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...2)))
        }
        return "\(text(lower))–\(text(upper))"
    }
}

private let maintain = SoilBandNote(tone: .good, effect: nil, action: "It's good. Maintain it.")

/// The standard for each measurement. All the limits and wording live here, so changing one is
/// a change to one place.
///
/// PLACEHOLDER. The ranges, effects and advice below are a first draft for flooded, regenerative
/// rice paddies. They have not been checked by an agronomist, they do not allow for flooded and
/// drained soil differing, for crop stage, or for a probe reading against a lab one, and they
/// leave no margin for a device's accuracy. Replace them before they are relied on. The app
/// says so wherever it shows them.
///
/// The source lists some gaps between bands (pH 5.5 to 6.0 and 7.8 to 7.9, potassium 100 to 120,
/// organic carbon 1.5 to 2.0). Each gap goes to the band below it for the low gaps, and to the
/// band above it for the top ones, which is the more cautious reading in both cases.
///
/// Fertilizer has no standard yet.
enum SoilStandards {
    /// Nitrogen, in mg/kg.
    static let nitrogen = SoilStandard(
        lower: 80, upper: 120, highUpper: 150,
        notes: [
            .low: SoilBandNote(
                tone: .act, effect: "Pale yellow leaves and weak tillering.",
                action: "Plant legume cover crops in the off-season, or introduce Azolla."),
            .standard: maintain,
            .high: SoilBandNote(
                tone: .good,
                effect:
                    "Deep green, vigorous growth and high yield potential, as long as the nitrogen is held in organic matter and not free synthetic nitrate.",
                action:
                    "It's good. Maintain it, but pause extra nitrogen inputs, and make sure potassium is also high so the stems stay strong."
            ),
            .excessive: SoilBandNote(
                tone: .act,
                effect:
                    "Weak, watery stems that fall over easily, and more brown planthoppers and blast disease.",
                action:
                    "Stop all nitrogen inputs, drain briefly (alternate wetting and drying) to slow uptake, and apply rice hull ash to toughen the stalks."
            ),
        ])

    /// Phosphorus, in mg/kg.
    static let phosphorus = SoilStandard(
        lower: 15, upper: 25, highUpper: 45,
        notes: [
            .low: SoilBandNote(
                tone: .act, effect: "Purplish leaves and poor roots.",
                action: "Apply rock phosphate together with phosphate-solubilizing bacteria."),
            .standard: maintain,
            .high: SoilBandNote(
                tone: .good,
                effect:
                    "Plenty of phosphorus for root development and early tillering, with no negative effects yet.",
                action:
                    "It's good. Maintain it. Stop adding outside phosphorus such as bone meal or poultry manure, and let the soil cycle what it already has."
            ),
            .excessive: SoilBandNote(
                tone: .act,
                effect:
                    "Blocks zinc and iron uptake, and risks polluting nearby waterways with algae.",
                action:
                    "Stop phosphorus-heavy manures, keep grass buffers on the bunds, and grow off-season cover crops to take up the excess."
            ),
        ])

    /// Potassium, in mg/kg.
    static let potassium = SoilStandard(
        lower: 120, upper: 180, highUpper: 280,
        notes: [
            .low: SoilBandNote(
                tone: .act, effect: "Scorched leaf edges and weak stems.",
                action: "Return all chopped rice straw, and apply rice hull or wood ash."),
            .standard: maintain,
            .high: SoilBandNote(
                tone: .good,
                effect:
                    "The strongest stems, better drought and heat tolerance, and heavy, well-filled grains.",
                action: "It's great. Maintain it by continuing to return rice straw."),
            .excessive: SoilBandNote(
                tone: .act,
                effect:
                    "Starts to crowd out magnesium and calcium, which can cause leaf-tip burn or chalky grain.",
                action:
                    "Pause ash applications, and add a light dose of dolomite lime or Epsom salts to restore the balance."
            ),
        ])

    static let ph = SoilStandard(
        lower: 6.0, upper: 7.2, highUpper: 7.8,
        notes: [
            .low: SoilBandNote(
                tone: .act,
                effect:
                    "Phosphorus gets locked up, and iron or aluminium can become toxic to the plants.",
                action: "Apply agricultural lime or dolomite while the field is dry and fallow."),
            .standard: maintain,
            .high: SoilBandNote(
                tone: .watch,
                effect:
                    "A small risk of zinc shortage, though flooding usually pulls the pH back toward neutral.",
                action:
                    "Mostly fine, but keep an eye on it. Use organic matter or compost rather than synthetic inputs, and add a zinc foliar spray only if rusty spots appear on the leaves."
            ),
            .excessive: SoilBandNote(
                tone: .act,
                effect: "Serious zinc and iron lock-out, and poor tillering.",
                action:
                    "Work in green manure such as Sesbania, apply elemental sulfur, and flush with fresh water."
            ),
        ])

    /// Soil organic carbon, as a percentage.
    static let organicCarbon = SoilStandard(
        lower: 2.0, upper: 3.5, highUpper: 6.0,
        notes: [
            .low: SoilBandNote(
                tone: .act, effect: "Hard, compacted soil that loses nutrients quickly.",
                action: "Stop burning straw, and use IMO or EM microbes and cover crops."),
            .standard: maintain,
            .high: SoilBandNote(
                tone: .good,
                effect:
                    "The soil holds a lot of water and nutrients, and supports very active soil life.",
                action:
                    "It's fantastic. Maintain it, and use alternate wetting and drying so this carbon does not turn into methane."
            ),
            .excessive: SoilBandNote(
                tone: .act,
                effect:
                    "In standing water, very high organic matter makes toxic organic acids and hydrogen sulfide gas that rot the roots.",
                action:
                    "Never plow raw straw into wet soil. Use strict alternate wetting and drying to keep oxygen reaching the roots, and watch for copper and zinc deficiency."
            ),
        ])
}
