import XCTest

@testable import AuraFarm

final class AdviceStepRulesTests: XCTestCase {
    /// Euglenoids dominant, fair: refresh_water and talk_extension are both on offer.
    private let context: AdviceContext = {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 10, moisture: .flooded,
            countsByClass: ["euglena": 10, "paramecium": 1], sweep: nil)
        let estimate = SoilHealthEstimate(
            level: .fair, score: nil, confidence: .low, reasons: [], followUp: "")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }()

    private func suggested(_ id: AdviceAction.ID) throws -> AdviceContext.SuggestedAction {
        let action = try XCTUnwrap(AdviceActions.action(id))
        return AdviceContext.SuggestedAction(action: action, because: "test", reason: "Approved reason.")
    }

    private func steps(_ ids: [AdviceAction.ID]) throws -> [Recommendation.Step] {
        try ids.map { AdviceStepRules.step(for: try suggested($0), why: nil) }
    }

    func testWithRoomTheExtensionStepIsAppended() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let result = AdviceStepRules.ensuringExtensionStep(try steps([.refreshWater]), offered: offered)

        XCTAssertEqual(result.map(\.actionID), [.refreshWater, .talkExtension])
        XCTAssertEqual(result.last?.why, AdviceReasons.extensionBeforeBiggerChanges)
    }

    func testWithThreeStepsTheLeastRelevantStepGoesAndTheExtensionComesLast() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)

        // Euglenoids dominant standard advice: alternate_wet_dry is furthest down the priority
        // order, and refresh_water still leaves a must-check action.
        let standard = AdviceStepRules.ensuringExtensionStep(
            try steps([.refreshWater, .reviewFertilizer, .alternateWetDry]), offered: offered)
        XCTAssertEqual(standard.map(\.actionID), [.refreshWater, .reviewFertilizer, .talkExtension])

        // Model picks: green manure is the least relevant, and refresh_water stays.
        let picks = AdviceStepRules.ensuringExtensionStep(
            try steps([.resampleFresh, .greenManure, .refreshWater]), offered: offered)
        XCTAssertEqual(picks.map(\.actionID), [.resampleFresh, .refreshWater, .talkExtension])
    }

    func testTheExtensionStepIsAlwaysLastAndAMustCheckActionAlwaysRemains() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let cases: [[AdviceAction.ID]] = [
            [.refreshWater], [.refreshWater, .resampleLater], [.refreshWater, .resampleLater, .greenManure],
            [.refreshWater, .alternateWetDry, .resampleFresh],
            [.greenManure, .reviewFertilizer, .refreshWater],
            [.resampleLater, .keepNotes, .alternateWetDry],
        ]
        for ids in cases {
            let result = AdviceStepRules.ensuringExtensionStep(try steps(ids), offered: offered)

            XCTAssertEqual(result.last?.actionID, .talkExtension, "\(ids)")
            XCTAssertTrue(
                result.contains { $0.actionID.flatMap { AdviceActions.action($0) }?.review == .must },
                "\(ids)")
            XCTAssertLessThanOrEqual(result.count, 3, "\(ids)")
        }
    }

    func testFewerThanThreeStepsAppendTheExtensionAtTheEnd() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let result = AdviceStepRules.ensuringExtensionStep(
            try steps([.refreshWater, .resampleLater]), offered: offered)

        XCTAssertEqual(result.map(\.actionID), [.refreshWater, .resampleLater, .talkExtension])
    }

    func testProtectedResamplesAreNeverDropped() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let result = AdviceStepRules.ensuringExtensionStep(
            try steps([.resampleFresh, .resampleTrust, .refreshWater]), offered: offered)

        // Only refresh_water could go, and it is the last must-check action: nothing changes.
        XCTAssertEqual(result.map(\.actionID), [.resampleFresh, .resampleTrust, .refreshWater])
    }

    func testNoCandidateMeansNoChange() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let steps = try steps([.resampleFresh, .refreshWater, .resampleTrust])

        XCTAssertEqual(AdviceStepRules.ensuringExtensionStep(steps, offered: offered), steps)
    }

    func testNothingChangesWithoutAMustCheckStepOrWhenThereIsNothingToAdd() throws {
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let noMust = try steps([.resampleLater, .keepNotes])
        XCTAssertEqual(AdviceStepRules.ensuringExtensionStep(noMust, offered: offered), noMust)

        let notOffered = offered.filter { $0.action.id != .talkExtension }
        let must = try steps([.refreshWater, .resampleLater])
        XCTAssertEqual(AdviceStepRules.ensuringExtensionStep(must, offered: notOffered), must)

        let already = try steps([.refreshWater, .talkExtension, .resampleLater])
        XCTAssertEqual(AdviceStepRules.ensuringExtensionStep(already, offered: offered), already)
    }

    func testEuglenoidsDominantStandardAdviceIncludesTheExtensionStep() {
        let result = SoilResult(
            sampleID: "DEMO", recordedAt: .now, framesKept: 12, moisture: .flooded,
            countsByClass: ["Euglena": 30, "Phacus": 8, "Paramecium": 3], sweep: nil)
        let context = AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result), history: [])

        let steps = RuleBasedRecommender.recommendation(for: context).steps

        XCTAssertTrue(context.patterns.contains(.euglenoidsDominant))
        XCTAssertTrue(steps.contains { $0.actionID == .talkExtension })
    }

    func testStepUsesTheApprovedReasonUnlessTheGivenOneHasText() throws {
        let action = try suggested(.keepNotes)

        for empty in [nil, "", "   \n"] as [String?] {
            XCTAssertEqual(AdviceStepRules.step(for: action, why: empty).why, "Approved reason.")
        }
        XCTAssertEqual(AdviceStepRules.step(for: action, why: " Own reason. ").why, "Own reason.")
        XCTAssertEqual(AdviceStepRules.step(for: action, why: nil).text, action.action.wording)
    }
}
