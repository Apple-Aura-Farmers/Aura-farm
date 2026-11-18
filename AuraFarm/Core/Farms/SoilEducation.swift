import Foundation

/// What a soil measurement does, and what each reading of it may mean, kept as fixed app data.
/// The screens, the PDF and the advice all read it from here, so every one of them says the same
/// thing. Apple Intelligence never writes it: the model is only given the short lines for the
/// readings that were recorded.
///
/// Three things are kept apart on purpose:
/// - the general education (`whatItDoes`, `whyStandardHelps`), true whatever the reading;
/// - what the current reading may mean (`meaning`), for the band it falls in;
/// - what, if anything, might be done about it (`action`), always careful and never a dose.
///
/// Nothing here is a diagnosis. A reading "may" mean something, and a farm's own soil type,
/// water and crop change what it does.
///
/// PLACEHOLDER: a first reviewed draft. No agronomist has checked it, and the app says so wherever
/// it shows it.
struct SoilEducation: Equatable {
    let name: String
    let whatItDoes: String
    /// Why the standard range is generally the favourable one.
    let whyStandardHelps: String
    /// What a reading in each band may mean.
    let meaning: [SoilBand: String]
    /// What might be done about a reading in each band. A band with no entry needs nothing.
    let action: [SoilBand: String]
    /// How each band should be read: a high potassium reading is good news and a high pH is not.
    let tones: [SoilBand: SoilTone]
    /// A limit on how far the education can be trusted. Only pH has one so far.
    let caveat: String?

    /// The words shown when a reading needs nothing done.
    static let noChange = "No change needed. Measure the same way next time so readings can be compared."

    /// The band's meaning and action as the older single note, for what still reads it.
    var notes: [SoilBand: SoilBandNote] {
        var notes: [SoilBand: SoilBandNote] = [:]
        for band in [SoilBand.low, .standard, .high, .excessive] {
            notes[band] = SoilBandNote(
                tone: tones[band] ?? .good, effect: meaning[band], action: action[band] ?? Self.noChange)
        }
        return notes
    }
}

extension SoilEducation {
    /// What the screens and the PDF show for one recorded reading.
    struct Detail: Equatable {
        let whatItDoes: String
        let whyStandardHelps: String
        let meaning: String?
        /// nil when the reading needs nothing done.
        let action: String?
        let caveat: String?
    }

    func detail(for band: SoilBand) -> Detail {
        Detail(
            whatItDoes: whatItDoes, whyStandardHelps: whyStandardHelps, meaning: meaning[band],
            action: action[band], caveat: caveat)
    }
}

extension SoilEducation {
    static let ph = SoilEducation(
        name: "pH",
        whatItDoes:
            "Controls soil acidity and affects which nutrients plants can take up. In flooded rice soils, pH often moves toward near-neutral conditions after flooding.",
        whyStandardHelps:
            "Nutrient availability is generally more balanced for rice, subject to soil type and flooding conditions.",
        meaning: [
            .low:
                "Some nutrients may become harder for plants to use, while iron, aluminium, or manganese may become more available.",
            .standard:
                "Nutrient availability is generally more balanced for rice, subject to soil type and flooding conditions.",
            .high:
                "A pH a little above the target may make phosphorus and some micronutrients less available. Flooding often moves it back toward neutral, so it is worth watching.",
            .excessive: "Phosphorus and some micronutrients may become less available.",
        ],
        action: [
            .low:
                "Ask an extension officer whether this pH matters for your flooded field before changing anything. Flooding can move the pH toward neutral.",
            .high:
                "Keep an eye on it and measure again in the same way. No change is needed yet.",
            .excessive:
                "Ask an extension officer whether this pH needs action for flooded rice before changing anything.",
        ],
        tones: [.low: .act, .standard: .good, .high: .watch, .excessive: .act],
        caveat: SoilEducation.phCaveat)

    /// Shown with every pH reading. It is the reason a pH outside the range never leads straight
    /// to an amendment.
    static let phCaveat =
        "A provisional target range for flooded rice soils is around pH 6.0–7.0. The best range depends on soil type, flooding duration, rice variety, and how the pH was measured. Flooding can move acidic or alkaline soils toward near-neutral pH, and the pH of dry, air-dried soil may differ from the pH around rice roots after flooding. A pH reading should be read with how and when it was measured, and a low or high value does not by itself call for any particular amendment."

    static let nitrogen = SoilEducation(
        name: "Nitrogen",
        whatItDoes: "Supports chlorophyll, leaves, stems, proteins, and plant growth.",
        whyStandardHelps: "Enough nitrogen is available without a clear excess signal.",
        meaning: [
            .low: "Plants may show pale leaves, weak growth, or poor tillering.",
            .standard: "Enough nitrogen is available without a clear excess signal.",
            .high:
                "More nitrogen than the standard. It can support strong growth, but how it behaves depends on whether it is held in organic matter or is free in the soil, so it is worth watching.",
            .excessive:
                "Plants may become overly lush or soft, with greater lodging, disease, or nutrient-imbalance risk.",
        ],
        action: [
            .low:
                "Grow a cover crop such as beans between seasons to keep living roots in the soil and add nitrogen. Ask an extension officer before a major change.",
            .high: "Hold off adding more nitrogen until the next check.",
            .excessive:
                "Hold back on extra nitrogen fertilizer, and ask an extension officer before making a major change.",
        ],
        tones: [.low: .act, .standard: .good, .high: .watch, .excessive: .act],
        caveat: nil)

    static let phosphorus = SoilEducation(
        name: "Phosphorus",
        whatItDoes:
            "Supports energy transfer, roots, cell membranes, flowering, seed formation, and maturity.",
        whyStandardHelps: "Enough is available for normal crop development.",
        meaning: [
            .low: "Root development and early plant growth may suffer.",
            .standard: "Enough is available for normal crop development.",
            .high:
                "More than the standard. Flooding often frees phosphorus already in the soil, so adding more is rarely needed.",
            .excessive:
                "Extra phosphorus may become less available to plants and may contribute to water-quality problems.",
        ],
        action: [
            .low:
                "Well-matured compost may help release the phosphorus already in the soil. Ask an extension officer before a major change.",
            .high: "No need to add more phosphorus for now.",
            .excessive:
                "Pause phosphorus-rich inputs such as manure, keep the ground covered, and ask an extension officer.",
        ],
        tones: [.low: .act, .standard: .good, .high: .watch, .excessive: .act],
        caveat: nil)

    static let potassium = SoilEducation(
        name: "Potassium",
        whatItDoes:
            "Helps regulate water movement, stomata, enzymes, carbohydrates, and stress tolerance.",
        whyStandardHelps: "Enough is available for normal plant functions.",
        meaning: [
            .low: "Plants may have weaker stems and poorer water regulation.",
            .standard: "Enough is available for normal plant functions.",
            .high:
                "More than the standard, which is often favorable for strong stems and water regulation.",
            .excessive: "Too much potassium may interfere with calcium or magnesium uptake.",
        ],
        action: [
            .low: "Leave crop residues on the soil surface as mulch, and return straw after harvest.",
            .excessive:
                "Pause potassium-rich inputs such as ash for a while, and ask an extension officer before a major change.",
        ],
        tones: [.low: .act, .standard: .good, .high: .good, .excessive: .act],
        caveat: nil)

    static let organicCarbon = SoilEducation(
        name: "Organic carbon",
        whatItDoes:
            "Is part of soil organic matter and supports soil structure, microbial activity, nutrient retention, and water-holding capacity.",
        whyStandardHelps: "The soil has a useful level of organic matter for its conditions.",
        meaning: [
            .low: "Soil may hold less water and nutrients and may have weaker structure.",
            .standard: "The soil has a useful level of organic matter for its conditions.",
            .high:
                "More organic matter than the standard. This is often favorable, as long as the soil still gets enough air.",
            .excessive:
                "Very high organic material may create oxygen or decomposition problems in wet soil, depending on the material, moisture, and drainage.",
        ],
        action: [
            .low:
                "Leave crop residues on the soil surface as mulch, and add well-matured compost.",
            .excessive:
                "Avoid adding more fresh organic material to wet soil, and ask an extension officer about drainage.",
        ],
        tones: [.low: .act, .standard: .good, .high: .good, .excessive: .act],
        caveat: nil)
}
