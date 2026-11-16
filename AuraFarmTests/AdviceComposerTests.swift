import XCTest

@testable import AuraFarm

/// Putting the soil steps beside the microscope steps, so "What to do next" shows both.
final class AdviceComposerTests: XCTestCase {
    private let quiet = ["paramecium": 20, "amoeba": 20]

    private func context(
        _ counts: [String: Int], level: SoilHealthEstimate.Level = .poor, soil: SoilMeasurements?
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 10, moisture: .flooded, countsByClass: counts,
            sweep: nil, cropStage: .fallow, recentActions: [], stoppedEarly: false, soil: soil)
        let estimate = SoilHealthEstimate(level: level, score: nil, confidence: .low, reasons: [], followUp: "Again.")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }

    private func standard(_ context: AdviceContext) -> Recommendation {
        RuleBasedRecommender.recommendation(for: context)
    }

    private let manySoil = SoilMeasurements(
        nitrogen: 60, phosphorus: 60, potassium: 100, ph: 5.5, organicCarbonPercent: 7)

    func testSummaryTellsTheFarmerToKeepGoingOnlyWhenEverySoilReadingIsStandard() {
        let good = context(quiet, level: .good, soil: SoilMeasurements(nitrogen: 100, phosphorus: 20, ph: 6.5))
        let once = AdviceComposer.combined(standard(good), context: good)
        XCTAssertTrue(once.summary.contains(AdviceComposer.soilAllGood))
        XCTAssertEqual(AdviceComposer.combined(once, context: good).summary, once.summary)

        let off = context(quiet, level: .good, soil: SoilMeasurements(nitrogen: 100, ph: 5.5))
        XCTAssertFalse(AdviceComposer.combined(standard(off), context: off).summary.contains(AdviceComposer.soilAllGood))
    }

    func testInorganicOnlyFertilizerAddsAnOrganicStepAndBlocksTheAllGoodLine() {
        func rec(_ type: FertilizerType) -> Recommendation {
            let ctx = context(quiet, level: .good, soil: SoilMeasurements(nitrogen: 100, fertilizerType: type))
            return AdviceComposer.combined(standard(ctx), context: ctx)
        }
        let inorganic = rec(.inorganic)
        XCTAssertEqual(inorganic.steps.first { $0.actionID == .addOrganicInput }?.group, .soil)
        XCTAssertFalse(inorganic.summary.contains(AdviceComposer.soilAllGood))
        for type in [FertilizerType.organic, .blend] {
            XCTAssertNil(rec(type).steps.first { $0.actionID == .addOrganicInput }, type.label)
            XCTAssertTrue(rec(type).summary.contains(AdviceComposer.soilAllGood), type.label)
        }
    }

    func testSoilStepsAlwaysAppearAfterTheMicroscopeSteps() {
        let ctx = context(["paramecium": 2], soil: manySoil)
        let combined = AdviceComposer.combined(standard(ctx), context: ctx)

        let groups = combined.steps.map(\.group)
        XCTAssertTrue(groups.contains(.microscope))
        XCTAssertTrue(groups.contains(.soil))
        // Microscope steps first, then soil steps, never mixed.
        let firstSoil = groups.firstIndex(of: .soil)!
        XCTAssertTrue(groups[..<firstSoil].allSatisfy { $0 == .microscope })
        XCTAssertTrue(groups[firstSoil...].allSatisfy { $0 == .soil })
        for id in [AdviceAction.ID.raisePH, .checkNutrientBalance, .reducePhosphorus] {
            XCTAssertEqual(combined.steps.first { $0.actionID == id }?.group, .soil, "\(id)")
        }
    }

    func testAModelPickOfASoilStepKeepsItsWordsAndMovesToTheSoilGroup() {
        let ctx = context(quiet, level: .good, soil: SoilMeasurements(ph: 5.5))
        let own = Recommendation.Step(
            actionID: .raisePH, text: AdviceActions.action(.raisePH)!.wording, why: "The model's own reason.",
            timing: "Before next planting")
        let rec = Recommendation(summary: "S", noticed: [], steps: [own], source: .foundationModel)

        let combined = AdviceComposer.combined(rec, context: ctx)

        XCTAssertEqual(combined.steps.filter { $0.actionID == .raisePH }.count, 1)
        XCTAssertEqual(combined.steps.first { $0.actionID == .raisePH }?.why, "The model's own reason.")
        XCTAssertEqual(combined.steps.first { $0.actionID == .raisePH }?.group, .soil)
        XCTAssertEqual(combined.summary, "S")
        XCTAssertEqual(combined.source, .foundationModel)
    }

    func testAStepBothSidesCallForAppearsOnceInTheMicroscopeGroup() {
        let ctx = context(["paramecium": 2], soil: SoilMeasurements(organicCarbonPercent: 1.5))
        let combined = AdviceComposer.combined(standard(ctx), context: ctx)

        let compost = combined.steps.filter { $0.actionID == .addCompost }
        XCTAssertLessThanOrEqual(compost.count, 1)
        for step in compost {
            XCTAssertEqual(step.group, .microscope)
            XCTAssertTrue(step.alsoFromSoil)
        }
    }

    func testTheExtensionOfficerAppearsOnceAndOnlyWhenNeeded() {
        let needs = context(quiet, level: .good, soil: SoilMeasurements(ph: 5.5))
        let combined = AdviceComposer.combined(standard(needs), context: needs)
        XCTAssertEqual(combined.steps.filter { $0.actionID == .talkExtension }.count, 1)

        let again = AdviceComposer.combined(combined, context: needs)
        XCTAssertEqual(again.steps.filter { $0.actionID == .talkExtension }.count, 1)

        let plain = context(quiet, level: .good, soil: SoilMeasurements(potassium: 100))
        // A soil step that needs no expert adds no extension step the sample did not already have.
        let fine = AdviceComposer.combined(standard(plain), context: plain)
        XCTAssertEqual(
            fine.steps.filter { $0.actionID == .talkExtension }.count,
            standard(plain).steps.filter { $0.actionID == .talkExtension }.count)
    }

    func testComposingTwiceGivesTheSameAdvice() {
        let ctx = context(["paramecium": 2], soil: manySoil)
        let once = AdviceComposer.combined(standard(ctx), context: ctx)
        XCTAssertEqual(AdviceComposer.combined(once, context: ctx), once)
    }

    func testWithoutSoilStepsTheAdviceIsNotGroupedOrChanged() {
        for soil in [nil, SoilMeasurements(), SoilMeasurements(nitrogen: 100, ph: 6.5)] {
            let ctx = context(["paramecium": 2], soil: soil)
            var rec = standard(ctx)
            // All-standard soil only adds the "keep going" sentence to the summary.
            if soil?.nitrogen != nil { rec.summary += " " + AdviceComposer.soilAllGood }
            XCTAssertEqual(AdviceComposer.combined(rec, context: ctx), rec)
            XCTAssertTrue(AdviceComposer.combined(rec, context: ctx).steps.allSatisfy { $0.group == nil })
        }
    }

    func testANotCountedSweepIsLeftAlone() {
        let ctx = context([:], level: .notCounted, soil: SoilMeasurements(ph: 5.5))
        let rec = standard(ctx)
        XCTAssertEqual(AdviceComposer.combined(rec, context: ctx), rec)
    }

    func testVeryHighCarbonNeverBringsBackStrawOrCompost() {
        let ctx = context(["paramecium": 2], soil: SoilMeasurements(organicCarbonPercent: 7))
        let combined = AdviceComposer.combined(standard(ctx), context: ctx)
        let ids = combined.steps.compactMap(\.actionID)
        for id in [AdviceAction.ID.returnStraw, .addCompost, .greenManure] {
            XCTAssertFalse(ids.contains(id), "\(id)")
        }
        XCTAssertTrue(ids.contains(.keepStrawOnTop))
    }

    func testTheSoilGroupIsCapped() {
        let ctx = context(["paramecium": 2], soil: manySoil)
        let combined = AdviceComposer.combined(standard(ctx), context: ctx)
        let soil = combined.steps.filter { $0.group == .soil && $0.actionID != .talkExtension }
        XCTAssertLessThanOrEqual(soil.count, AdviceComposer.maxSoilSteps)
    }

    func testAdviceSavedBeforeGroupsStillDecodes() throws {
        let old = #"{"actionID":"keep_notes","text":"Kept","why":"Why","timing":"Now"}"#
        let step = try JSONDecoder().decode(Recommendation.Step.self, from: Data(old.utf8))
        XCTAssertNil(step.group)
        XCTAssertFalse(step.alsoFromSoil)
        let round = try JSONDecoder().decode(
            Recommendation.Step.self, from: JSONEncoder().encode(AdviceComposer.combined(
                Recommendation(summary: "", noticed: [], steps: [step], source: .rules),
                context: context(["paramecium": 2], soil: manySoil)).steps[0]))
        XCTAssertEqual(round.group, .microscope)
    }
}
