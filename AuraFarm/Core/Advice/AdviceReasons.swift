import Foundation

/// The plain reason shown with each step, for a field helper to read aloud. The model is given
/// these to build on, and they are shown when the model's own reason is missing or fails a
/// check.
///
/// The sentences mirror Table B2 in `docs/advice-content.md` (the team's "Advice content",
/// approved 9 November 2026). Change them in both places.
///
/// PLACEHOLDER copy written for the prototype, not by an agronomist.
enum AdviceReasons {
    static let tooFewToSay = "Too little was seen to judge the soil."
    static let nothingReadable = "What was seen can't be read yet."
    static let mixedSignals = "The signs in this sample point different ways."
    static let onlyOneKind = "Only one kind of organism was seen, which is too narrow to judge."
    static let stoppedEarly = "The sweep stopped before it finished."
    static let fewFrames = "Only a small part of the slide was looked at."
    static let drained = "The field was drained, and dry soil hides many organisms."
    static let sampleVaries = "One sample can vary, so a second one shows whether this holds."
    static let misidentified = "Some organisms in this sample may have been misidentified."
    static let plentyOfLife = "Plenty of soil life was seen, of several kinds."
    static let strawLowAbundance = "Not much soil life was seen, and straw is food for it."
    static let strawLowDiversity = "Only a few kinds of organism were seen, and straw feeds a wider range."
    static let burning = "Little soil life was seen, and burning removes the food it needs."
    static let compost = "Not much soil life was seen, and compost feeds it."
    static let coverCropLowAbundance = "Little soil life was seen, and a cover crop adds food for it."
    static let coverCropLowDiversity =
        "Only a few kinds of organism were seen, and a cover crop adds food for more."
    static let stillWater =
        "Many Euglena-type organisms were seen, which often means still, nutrient-rich water."
    static let airInSoil = "Still, nutrient-rich water can be short of air, and a short drain lets air in."
    static let fertilizerAfterFertilizing =
        "Seen soon after fertilizing, this can mean more nutrients than the crop needs."
    static let fertilizer = "A sample like this can mean more nutrients than the crop needs."
    static let rootPests =
        "Many tiny worms were seen. Some kinds feed on rice roots, and the app can't tell which."
    static let extensionAfterPoor = "Little soil life was seen, so an expert view helps before acting."
    static let extensionBeforeBiggerChanges =
        "Some of these steps are bigger changes, so it's worth asking first."
    static let lowTwice = "This plot looked low twice in a row."
    static let notes = "Notes make the next sample easier to compare."
    /// For the two fixed steps of a sweep that was never counted.
    static let notCounted = "Counting didn't run on this sweep."

    /// Every sentence this file can return, in a fixed order. The content version is worked out
    /// from it, and a test checks that every reason the builder produces is in it.
    static let allSentences: [String] = [
        tooFewToSay, nothingReadable, mixedSignals, onlyOneKind, stoppedEarly, fewFrames, drained,
        sampleVaries, misidentified, plentyOfLife, strawLowAbundance, strawLowDiversity, burning, compost,
        coverCropLowAbundance, coverCropLowDiversity, stillWater, airInSoil, fertilizerAfterFertilizing,
        fertilizer, rootPests, extensionAfterPoor, extensionBeforeBiggerChanges, lowTwice, notes, notCounted,
    ]
}
