import Foundation

/// The approved actions, in catalogue order.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist. Rows marked `.must` need expert review.
enum AdviceActions {
    static let all: [AdviceAction] = [
        AdviceAction(
            id: .resampleFresh, wording: "Make a fresh slide and sweep again before changing anything.",
            cost: "None", effort: "Low", timing: "Now", review: .light),
        AdviceAction(
            id: .resampleFlooded,
            wording: "Sample again once the field is flooded. Dry soil hides many organisms.",
            cost: "None", effort: "Low", timing: "Next flooding", review: .should),
        AdviceAction(
            id: .resampleLater,
            wording: "Sample this field again in 2 to 4 weeks, the same way, to see if it changes.",
            cost: "None", effort: "Low", timing: "2 to 4 weeks", review: .light),
        AdviceAction(
            id: .resampleTrust, wording: "Sample again; some organisms may have been misidentified.",
            cost: "None", effort: "Low", timing: "Now", review: .light),
        AdviceAction(
            id: .keepPractice, wording: "Keep doing what you're doing in this field.",
            cost: "None", effort: "None", timing: "Any time", review: .light),
        AdviceAction(
            id: .returnStraw, wording: "Work leftover rice straw back into the soil instead of burning it.",
            cost: "None", effort: "Medium", timing: "After harvest", review: .must),
        AdviceAction(
            id: .stopBurning, wording: "Avoid burning straw. It removes food for soil life.",
            cost: "None", effort: "Low", timing: "After harvest", review: .should),
        AdviceAction(
            id: .addCompost, wording: "Add well-rotted compost or manure if you have it.",
            cost: "Low", effort: "Medium", timing: "Before planting", review: .must),
        AdviceAction(
            id: .greenManure, wording: "Between seasons, grow a cover crop like beans and dig it in.",
            cost: "Low", effort: "Medium", timing: "Next fallow", review: .should),
        AdviceAction(
            id: .refreshWater,
            wording: "Try not to let water sit still for long. Let fresh water flow in where you can.",
            cost: "None", effort: "Low to Medium", timing: "This week", review: .must),
        AdviceAction(
            id: .alternateWetDry,
            wording: "Ask about draining the field briefly mid-season, then reflooding. It lets air "
                + "into the soil.",
            cost: "None", effort: "Medium", timing: "Mid-season", review: .must),
        AdviceAction(
            id: .reviewFertilizer,
            wording: "Check with your extension officer whether you're using more fertilizer than the "
                + "crop needs.",
            cost: "Saves money", effort: "Low", timing: "Before next application", review: .should),
        AdviceAction(
            id: .checkRootPests,
            wording: "If plants look stunted or roots have swellings, ask your extension officer about "
                + "root worms.",
            cost: "None", effort: "Low", timing: "This week", review: .should),
        AdviceAction(
            id: .talkExtension, wording: "Talk to your local extension officer before making big changes.",
            cost: "None", effort: "Low", timing: "Before acting", review: .light),
        AdviceAction(
            id: .labTest, wording: "If the result stays low, send a soil sample to a lab.",
            cost: "Medium", effort: "Low", timing: "After a second poor result", review: .light),
        AdviceAction(
            id: .keepNotes,
            wording: "Write down what you did in this field, so the next sample can be compared fairly.",
            cost: "None", effort: "Low", timing: "Now", review: .light),
    ]

    /// The order used when the app, not the model, chooses actions: for standard advice, and
    /// to fill in when the model picked too few. Sampling again comes first.
    ///
    /// PLACEHOLDER: an order for the team to review.
    static let fallbackPriority: [AdviceAction.ID] = [
        .resampleTrust, .resampleFresh, .resampleFlooded, .checkRootPests, .refreshWater, .reviewFertilizer,
        .alternateWetDry, .returnStraw, .addCompost, .stopBurning, .greenManure, .keepPractice,
        .resampleLater,
        .labTest, .talkExtension, .keepNotes,
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Every ID has a row; a test checks it.
    static func action(_ id: AdviceAction.ID) -> AdviceAction? {
        byID[id]
    }
}
