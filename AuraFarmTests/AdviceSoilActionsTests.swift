import XCTest

@testable import AuraFarm

/// The actions the soil measurements a field helper recorded call for, and how they sit beside
/// the ones the microscope calls for.
final class AdviceSoilActionsTests: XCTestCase {
    private func context(
        _ counts: [String: Int],
        level: SoilHealthEstimate.Level = .fair,
        frames: Int = 10,
        moisture: SampleDetails.Moisture = .flooded,
        stage: SampleDetails.CropStage? = nil,
        recent: [SampleDetails.RecentAction] = [],
        soil: SoilMeasurements? = nil
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: frames, moisture: moisture, countsByClass: counts,
            sweep: nil, cropStage: stage, recentActions: recent, stoppedEarly: false, soil: soil)
        let estimate = SoilHealthEstimate(
            level: level, score: nil, confidence: .low, reasons: [], followUp: "Test again.")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }

    private func ids(_ context: AdviceContext) -> [AdviceAction.ID] { context.actions.map(\.action.id) }

    private func suggested(_ context: AdviceContext, _ id: AdviceAction.ID) -> AdviceContext.SuggestedAction? {
        context.actions.first { $0.action.id == id }
    }

    /// A sample whose microscope side offers little of its own, so what the soil adds stands out.
    private let quiet = ["paramecium": 20, "amoeba": 20]

    // MARK: Nothing recorded

    func testWithoutReadableMeasurementsTheActionsAreExactlyWhatTheyWere() {
        let plain = context(quiet, level: .good)

        XCTAssertEqual(plain.actions, context(quiet, level: .good, soil: nil).actions)
        XCTAssertEqual(plain.actions, context(quiet, level: .good, soil: SoilMeasurements()).actions)
        XCTAssertEqual(
            plain.actions,
            context(
                quiet, level: .good,
                soil: SoilMeasurements(fertilizerProduct: "Urea", fertilizerKilogramsPerHectare: 50)
            ).actions)
        XCTAssertFalse(plain.actions.contains { $0.fromSoil })
    }

    func testStandardAndHighReadingsAskForNothing() {
        // Nitrogen 100 is standard, 130 is high; potassium 200 is high; pH 6.5 and carbon 3 are standard.
        let soil = SoilMeasurements(
            nitrogen: 130, potassium: 200, ph: 6.5, organicCarbonPercent: 3)

        XCTAssertFalse(context(quiet, level: .good, soil: soil).actions.contains { $0.fromSoil })
    }

    // MARK: One action for each reading

    func testEachLowOrExcessiveReadingCallsForItsOwnAction() {
        let cases: [(SoilMeasurements, AdviceAction.ID, String)] = [
            (SoilMeasurements(ph: 5.5), .raisePH, AdviceReasons.phLow),
            (SoilMeasurements(ph: 8.0), .lowerPH, AdviceReasons.phHigh),
            (SoilMeasurements(nitrogen: 60), .boostNitrogen, AdviceReasons.nitrogenLow),
            (SoilMeasurements(nitrogen: 200), .reduceNitrogen, AdviceReasons.nitrogenExcess),
            (SoilMeasurements(phosphorus: 10), .unlockPhosphorus, AdviceReasons.phosphorusLow),
            (SoilMeasurements(phosphorus: 60), .reducePhosphorus, AdviceReasons.phosphorusExcess),
            (SoilMeasurements(potassium: 100), .boostPotassium, AdviceReasons.potassiumLow),
            (SoilMeasurements(potassium: 300), .reducePotassium, AdviceReasons.potassiumExcess),
        ]
        for (soil, id, reason) in cases {
            let found = suggested(context(quiet, level: .good, soil: soil), id)

            XCTAssertNotNil(found, "\(id)")
            XCTAssertEqual(found?.reason, reason, "\(id)")
            XCTAssertEqual(found?.fromSoil, true, "\(id)")
        }
    }

    func testOnlyTheOneReadingsActionIsAddedForASingleReading() {
        let context = context(quiet, level: .good, soil: SoilMeasurements(ph: 5.5))

        XCTAssertEqual(context.actions.filter(\.fromSoil).map(\.action.id), [.raisePH])
    }

    func testAnActionThatNeedsAnExpertBringsTheExtensionOfficer() {
        let withPH = context(quiet, level: .good, soil: SoilMeasurements(ph: 5.5))
        XCTAssertEqual(AdviceActions.action(.raisePH)?.review, .must)
        XCTAssertEqual(suggested(withPH, .talkExtension)?.because, "big changes suggested")

        // A reading whose action needs no expert adds nothing to what the sample already asked for.
        let withPotassium = context(quiet, level: .good, soil: SoilMeasurements(potassium: 100))
        XCTAssertEqual(
            suggested(withPotassium, .talkExtension), suggested(context(quiet, level: .good), .talkExtension))
    }

    // MARK: Organic carbon

    func testLowCarbonCallsForStrawAndCompost() {
        let soil = SoilMeasurements(organicCarbonPercent: 1.5)
        let context = context(["paramecium": 40, "amoeba": 40, "vorticella": 30, "arcellinida": 20], level: .good, soil: soil)

        XCTAssertEqual(suggested(context, .returnStraw)?.reason, AdviceReasons.carbonLowStraw)
        XCTAssertEqual(suggested(context, .addCompost)?.reason, AdviceReasons.carbonLowCompost)
        XCTAssertEqual(suggested(context, .returnStraw)?.fromSoil, true)
    }

    func testLowCarbonSkipsWhatWasJustDoneOrDoesNotSuitTheStage() {
        let soil = SoilMeasurements(organicCarbonPercent: 1.5)

        let seedling = context(quiet, level: .good, stage: .seedling, soil: soil)
        XCTAssertFalse(ids(seedling).contains(.returnStraw))
        XCTAssertTrue(ids(seedling).contains(.addCompost))

        let strawDone = context(quiet, level: .good, recent: [.addedStraw], soil: soil)
        XCTAssertNotEqual(suggested(strawDone, .returnStraw)?.reason, AdviceReasons.carbonLowStraw)
        let compostDone = context(quiet, level: .good, recent: [.addedCompost], soil: soil)
        XCTAssertNotEqual(suggested(compostDone, .addCompost)?.reason, AdviceReasons.carbonLowCompost)
    }

    func testBothTheMicroscopeAndTheCarbonCallingForAnActionIsOneActionWithBothReasonsNoted() {
        let lowLife = context(
            ["paramecium": 2], level: .poor, stage: .fallow, soil: SoilMeasurements(organicCarbonPercent: 1.5))

        let compost = suggested(lowLife, .addCompost)
        XCTAssertEqual(ids(lowLife).filter { $0 == .addCompost }.count, 1)
        XCTAssertEqual(compost?.reason, AdviceReasons.carbonLowCompost)
        XCTAssertEqual(compost?.because, "low abundance; organic carbon low")
        XCTAssertEqual(compost?.fromSoil, true)
    }

    func testVeryHighCarbonKeepsStrawOnTopAndArguesAgainstAddingMore() {
        let soil = SoilMeasurements(organicCarbonPercent: 7)
        // On its own the sample would suggest straw, compost and a cover crop.
        let without = context(["paramecium": 2], level: .poor, stage: .fallow)
        XCTAssertTrue(ids(without).contains(.returnStraw))
        XCTAssertTrue(ids(without).contains(.addCompost))
        XCTAssertTrue(ids(without).contains(.greenManure))

        let with = context(["paramecium": 2], level: .poor, stage: .fallow, soil: soil)

        XCTAssertEqual(suggested(with, .keepStrawOnTop)?.reason, AdviceReasons.carbonExcessStraw)
        XCTAssertEqual(suggested(with, .alternateWetDry)?.reason, AdviceReasons.carbonExcessAir)
        for id in [AdviceAction.ID.returnStraw, .addCompost, .greenManure] {
            XCTAssertFalse(ids(with).contains(id), "\(id)")
        }
    }

    func testAirIsOnlyAskedForOnWetSoilOutsideFlowering() {
        let soil = SoilMeasurements(organicCarbonPercent: 7)

        XCTAssertNil(suggested(context(quiet, level: .good, moisture: .drained, soil: soil), .alternateWetDry))
        XCTAssertNil(suggested(context(quiet, level: .good, stage: .flowering, soil: soil), .alternateWetDry))
        XCTAssertNil(suggested(context(quiet, level: .good, recent: [.drained], soil: soil), .alternateWetDry))
    }

    // MARK: Balance

    func testTwoReadingsOffTheirStandardCallForABalanceCheck() {
        let soil = SoilMeasurements(nitrogen: 60, phosphorus: 60)

        let context = context(quiet, level: .good, soil: soil)

        XCTAssertEqual(suggested(context, .checkNutrientBalance)?.reason, AdviceReasons.nutrientImbalance)
        XCTAssertTrue(ids(context).contains(.boostNitrogen))
        XCTAssertTrue(ids(context).contains(.reducePhosphorus))
    }

    func testOneShortWhileAnotherIsHighCallsForABalanceCheck() {
        let soil = SoilMeasurements(nitrogen: 60, potassium: 200)

        XCTAssertNotNil(suggested(context(quiet, level: .good, soil: soil), .checkNutrientBalance))
    }

    func testOneReadingOffAloneDoesNot() {
        XCTAssertNil(
            suggested(context(quiet, level: .good, soil: SoilMeasurements(nitrogen: 60)), .checkNutrientBalance))
        XCTAssertNil(
            suggested(
                context(quiet, level: .good, soil: SoilMeasurements(nitrogen: 130, potassium: 200)),
                .checkNutrientBalance))
    }

    // MARK: Beside the microscope

    func testAHardToReadSampleStillGetsTheSoilActionsButNotMicroscopeImprovements() {
        // Nothing here can be read, so the microscope's own improvement actions are held back.
        let context = context(["stentor": 6], soil: SoilMeasurements(ph: 5.5, organicCarbonPercent: 1.5))

        XCTAssertTrue(context.patterns.contains(.nothingInterpretable))
        XCTAssertTrue(ids(context).contains(.raisePH))
        XCTAssertTrue(ids(context).contains(.talkExtension))
        XCTAssertTrue(ids(context).contains(.resampleFresh))
    }

    func testTheSoilDoesNotChangeTheMicroscopesFacts() {
        let counts = ["euglena": 30, "phacus": 8, "paramecium": 3]
        let without = context(counts, level: .poor, stage: .tillering)
        let with = context(
            counts, level: .poor, stage: .tillering, soil: SoilMeasurements(nitrogen: 60, ph: 8.0))

        XCTAssertEqual(with.estimate, without.estimate)
        XCTAssertEqual(with.patterns, without.patterns)
        XCTAssertEqual(with.cautions, without.cautions)
        // What the microscope called for is all still there, unchanged.
        XCTAssertEqual(with.actions.filter { !$0.fromSoil }, without.actions)
        XCTAssertEqual(with.actions.filter(\.fromSoil).map(\.action.id), [.lowerPH, .boostNitrogen])
    }

    func testTheSoilStepsAreAddedWhenTheSampleAloneWouldFillTheList() {
        let soil = SoilMeasurements(
            nitrogen: 60, phosphorus: 60, potassium: 100, ph: 5.5, organicCarbonPercent: 7)
        let context = context(["paramecium": 2], level: .poor, stage: .fallow, soil: soil)

        // The model is only offered the microscope and general steps.
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        XCTAssertFalse(offered.contains { $0.fromSoil && !$0.fromMicroscope })
        XCTAssertLessThanOrEqual(offered.count, AdvicePromptBuilder.maxActions + 1)

        // Whatever it picks, the combined advice carries every soil step beside them.
        let picked = RuleBasedRecommender.recommendation(for: context)
        let combined = AdviceComposer.combined(picked, context: context)
        let soilSteps = combined.steps.filter { $0.group == .soil }.compactMap(\.actionID)
        for id in [AdviceAction.ID.raisePH, .checkNutrientBalance, .reducePhosphorus, .boostPotassium] {
            XCTAssertTrue(soilSteps.contains(id), "\(id)")
        }
        XCTAssertEqual(soilSteps.filter { $0 == .talkExtension }.count + combined.steps.filter { $0.actionID == .talkExtension }.count > 0, true)
        XCTAssertEqual(combined.steps.filter { $0.actionID == .talkExtension }.count, 1)
        XCTAssertLessThanOrEqual(soilSteps.count, AdviceComposer.maxSoilSteps + 1)
    }

    func testWithoutMeasurementsTrimmingIsUnchanged() {
        let counts = ["euglena": 30, "nematode": 30, "paramecium": 1]
        let plain = context(counts, level: .poor, frames: 12)
        let empty = context(counts, level: .poor, frames: 12, soil: SoilMeasurements())

        XCTAssertEqual(
            AdvicePromptBuilder.offeredActions(for: plain), AdvicePromptBuilder.offeredActions(for: empty))
    }

    // MARK: Words

    func testTheNewReasonsAreApprovedSentences() {
        let soil = SoilMeasurements(
            nitrogen: 200, phosphorus: 60, potassium: 300, ph: 5.5, organicCarbonPercent: 7)
        for soil in [
            soil, SoilMeasurements(ph: 8.0, organicCarbonPercent: 1.5),
            SoilMeasurements(nitrogen: 60, phosphorus: 10, potassium: 100),
        ] {
            let sentences = Set(AdviceReasons.allSentences)
            for suggested in context(quiet, level: .good, soil: soil).actions {
                XCTAssertTrue(sentences.contains(suggested.reason), "\(suggested.action.id): \(suggested.reason)")
            }
        }
    }

    func testTheNewActionsAreWordedLikeTheOthers() {
        let new: [AdviceAction.ID] = [
            .raisePH, .lowerPH, .boostNitrogen, .reduceNitrogen, .unlockPhosphorus, .reducePhosphorus,
            .boostPotassium, .reducePotassium, .keepStrawOnTop, .checkNutrientBalance,
        ]
        for id in new {
            let action = AdviceActions.action(id)
            let wording = action?.wording ?? ""

            XCTAssertFalse(wording.isEmpty, "\(id)")
            XCTAssertLessThanOrEqual(wording.split(separator: " ").count, 20, wording)
            for word in NeverSay.bannedWords + NeverSay.bannedPhrases {
                XCTAssertFalse(wording.lowercased().contains(word), wording)
            }
            // No amounts, and no digits at all.
            XCTAssertNil(wording.rangeOfCharacter(from: .decimalDigits), wording)
        }
    }

    func testThePromptTellsTheModelWhichActionsComeFromTheSoil() {
        let context = context(quiet, level: .good, soil: SoilMeasurements(ph: 5.5))
        let prompt = AdvicePromptBuilder.prompt(for: context)

        XCTAssertTrue(prompt.contains("The soil steps listed at the end come from them."))
        XCTAssertTrue(prompt.contains("Soil steps the app will also show (do not pick these"))
        XCTAssertTrue(prompt.contains("- \(AdviceActions.action(.raisePH)?.wording ?? "") (why:"))
        // The model is not asked to pick it.
        XCTAssertFalse(prompt.contains("- raise_ph:"))
        XCTAssertTrue(AdvicePromptBuilder.instructions().contains("Soil steps come from the helper's soil measurements"))
    }

    // MARK: Standard advice

    func testStandardAdviceUsesTheSoilActionsAndSaysSo() {
        let context = context(["paramecium": 2], level: .poor, stage: .fallow, soil: SoilMeasurements(ph: 5.5))
        let recommendation = AdviceComposer.combined(
            RuleBasedRecommender.recommendation(for: context), context: context)

        XCTAssertEqual(recommendation.steps.first { $0.actionID == .raisePH }?.group, .soil)
        XCTAssertTrue(recommendation.summary.hasSuffix("The soil measurements point to a few changes too."))
    }

    func testStandardAdviceIsUnchangedWithoutMeasurements() {
        let plain = context(["paramecium": 2], level: .poor, stage: .fallow)

        XCTAssertFalse(RuleBasedRecommender.summary(for: plain).contains("soil measurements"))
        XCTAssertEqual(
            RuleBasedRecommender.recommendation(for: plain),
            RuleBasedRecommender.recommendation(
                for: context(["paramecium": 2], level: .poor, stage: .fallow, soil: SoilMeasurements())))
    }
}
