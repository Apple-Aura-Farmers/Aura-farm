import Foundation

/// The fixed test set of samples, run on every build and on a phone from the Advice check.
///
/// PROVISIONAL: the expectations follow the rules in `docs/advice-content.md` as written; they
/// are not checked by an agronomist. Where a case states no level, the level is what the
/// placeholder estimator gives for its counts.
enum AdviceEvalCases {
    private static let recordedAt = Date(timeIntervalSince1970: 1_793_000_000)

    private static func make(
        _ id: String, _ title: String, _ counts: [String: Int]?, frames: Int = 12,
        moisture: SampleDetails.Moisture = .flooded, stage: SampleDetails.CropStage? = nil,
        recent: [SampleDetails.RecentAction] = [], plot: String? = nil, history: [PastResult] = [],
        level: SoilHealthEstimate.Level, match: Set<AdvicePattern> = [], notMatch: Set<AdvicePattern> = [],
        offer: Set<AdviceAction.ID> = [], notOffer: Set<AdviceAction.ID> = []
    ) -> AdviceEvalCase {
        AdviceEvalCase(
            id: id, title: title,
            result: SoilResult(
                sampleID: id, recordedAt: recordedAt, framesKept: frames, moisture: moisture,
                countsByClass: counts, sweep: nil, plotName: plot, cropStage: stage, recentActions: recent),
            history: history, expectedLevel: level, mustMatch: match, mustNotMatch: notMatch,
            mustOffer: offer, mustNotOffer: notOffer)
    }

    private static let euglenoids = ["Euglena": 30, "Phacus": 8, "Paramecium": 3]

    static let all: [AdviceEvalCase] = [
        make(
            "good-varied", "Plenty of life, several kinds",
            ["Paramecium": 22, "Euglena": 14, "Vorticella": 9, "Amoeba": 6, "Didinium": 3, "Dinobryon": 2],
            level: .good, match: [.severalRoles], notMatch: [.euglenoidsDominant, .cleanWaterAlgae],
            offer: [.keepPractice], notOffer: [.refreshWater]),
        make(
            "fair-ordinary", "Some life", ["Paramecium": 9, "Euglena": 6, "Vorticella": 3],
            level: .fair, offer: [.resampleLater], notOffer: [.keepPractice]),
        make(
            "poor-euglena-only", "Little life, only Euglena", ["Euglena": 7], frames: 30,
            level: .poor, match: [.euglenoidsDominant, .onlyOneKind],
            offer: [.refreshWater, .reviewFertilizer, .talkExtension, .resampleLater],
            notOffer: [.addCompost, .returnStraw]),
        make(
            "euglenoids-fertilized", "Mostly Euglena, fertilized lately", euglenoids, stage: .tillering,
            recent: [.fertilized], level: .good, match: [.euglenoidsDominant],
            offer: [.refreshWater, .reviewFertilizer, .talkExtension, .alternateWetDry],
            notOffer: [.keepPractice, .addCompost, .returnStraw]),
        make(
            "euglenoids-flowering", "Mostly Euglena, field flowering", euglenoids, stage: .flowering,
            level: .good, match: [.euglenoidsDominant], notOffer: [.alternateWetDry, .keepPractice]),
        make(
            "euglenoids-drained", "Mostly Euglena, field drained", euglenoids, moisture: .drained,
            level: .good, match: [.euglenoidsDominant], notOffer: [.alternateWetDry]),
        make(
            "clean-water-algae", "Clean-water algae present",
            ["Dinobryon": 4, "Micrasterias": 3, "Vorticella": 10, "Paramecium": 8, "Amoeba": 6],
            level: .good, match: [.cleanWaterAlgae], notOffer: [.addCompost, .returnStraw]),
        make(
            "mixed-signals", "Signs point different ways", ["Euglena": 40, "Dinobryon": 3, "Paramecium": 6],
            level: .good, match: [.mixedSignals], notMatch: [.euglenoidsDominant, .cleanWaterAlgae],
            offer: [.resampleFresh], notOffer: [.refreshWater, .keepPractice, .addCompost]),
        make(
            "predator-low-prey", "A predator and little prey",
            ["Didinium": 4, "Paramecium": 2, "Vorticella": 12, "Euglena": 5],
            level: .fair, match: [.predatorWithLowPrey, .severalRoles]),
        make(
            "nematodes-high", "Many nematodes", ["Nematode": 30, "Paramecium": 10, "Amoeba": 8],
            level: .good, match: [.nematodesHigh], offer: [.checkRootPests], notOffer: [.keepPractice]),
        make(
            "misidentification", "A sea organism in a paddy sample",
            ["Pyrocystis": 10, "Paramecium": 12, "Euglena": 6],
            level: .fair, match: [.possibleMisidentification], offer: [.resampleTrust],
            notOffer: [.returnStraw, .greenManure, .addCompost]),
        make(
            "review-pile-only", "Only organisms that aren't read",
            ["Stentor": 6, "Volvox": 5, "Closterium": 3],
            level: .fair, match: [.nothingInterpretable], offer: [.resampleFresh],
            notOffer: [.returnStraw, .stopBurning, .addCompost, .greenManure]),
        make(
            "drained-low", "Drained field, low counts", ["Paramecium": 6, "Arcellinida": 4],
            moisture: .drained, stage: .ripening, level: .poor, match: [.drainedLowCounts],
            offer: [.resampleFlooded]),
        make("too-few", "Too few to say", ["Paramecium": 2, "Euglena": 1], level: .tooFewToSay),
        make("not-counted", "Counting didn't run", nil, level: .notCounted),
        make("empty-slide", "Nothing on the slide", [:], level: .tooFewToSay),
        make(
            "poor-twice", "Poor twice in a row", ["Euglena": 3, "Paramecium": 3], plot: "North 2",
            history: [
                PastResult(
                    recordedAt: recordedAt.addingTimeInterval(-15 * 86_400), moisture: .flooded,
                    cropStage: nil,
                    organismsPerFrame: 0.4, interpretedKinds: 2, level: .poor)
            ], level: .poor, offer: [.labTest, .talkExtension]),
        make(
            "seedling-low", "Little life at the seedling stage", ["Paramecium": 5, "Vorticella": 3],
            stage: .seedling, level: .poor, notOffer: [.returnStraw, .greenManure]),
        make(
            "short-sweep", "A short sweep", ["Paramecium": 10, "Euglena": 5], frames: 3,
            level: .good, offer: [.resampleFresh]),
        make(
            "testate-rich", "Many testate amoebae", ["Arcellinida": 15, "Paramecium": 10, "Amoeba": 8],
            level: .fair, match: [.plentyOfTestateAmoebae]),
        make(
            "bundled-labels-good", "Bundled model's labels",
            ["paramecium": 22, "euglena": 14, "vorticella": 9, "stentor": 6, "volvox": 4], level: .good),
    ]
}
