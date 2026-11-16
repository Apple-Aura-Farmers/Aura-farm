import Foundation

/// One approved action the advice may suggest. The model picks from these and never adds
/// its own.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist. Rows marked `.must` need expert review.
struct AdviceAction: Equatable {
    /// In catalogue order, which is also the order actions are listed in.
    enum ID: String, CaseIterable, Codable {
        case resampleFresh = "resample_fresh"
        case resampleFlooded = "resample_flooded"
        case resampleLater = "resample_later"
        case resampleTrust = "resample_trust"
        case keepPractice = "keep_practice"
        case returnStraw = "return_straw"
        case stopBurning = "stop_burning"
        case addCompost = "add_compost"
        case greenManure = "green_manure"
        case refreshWater = "refresh_water"
        case alternateWetDry = "alternate_wet_dry"
        case reviewFertilizer = "review_fertilizer"
        case checkRootPests = "check_root_pests"
        case talkExtension = "talk_extension"
        case labTest = "lab_test"
        case keepNotes = "keep_notes"
        // From the soil measurements the field helper recorded. They come last so a sample with
        // no measurements lists its actions exactly as before.
        case raisePH = "raise_ph"
        case lowerPH = "lower_ph"
        case boostNitrogen = "boost_nitrogen"
        case reduceNitrogen = "reduce_nitrogen"
        case unlockPhosphorus = "unlock_phosphorus"
        case reducePhosphorus = "reduce_phosphorus"
        case boostPotassium = "boost_potassium"
        case reducePotassium = "reduce_potassium"
        case keepStrawOnTop = "keep_straw_on_top"
        case checkNutrientBalance = "check_nutrient_balance"
        case addOrganicInput = "add_organic_input"
    }

    var id: ID
    /// To be read aloud.
    var wording: String
    /// "None", "Low", "Medium" or "Saves money".
    var cost: String
    var effort: String
    var timing: String
    var review: OrganismNote.ReviewNeed
}
