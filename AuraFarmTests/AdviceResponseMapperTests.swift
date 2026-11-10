import XCTest

@testable import AuraFarm

final class AdviceResponseMapperTests: XCTestCase {
    /// Euglenoids dominant, fair: several actions on offer, one of them must-check.
    private let context: AdviceContext = {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 10, moisture: .flooded,
            countsByClass: ["euglena": 10, "paramecium": 1], sweep: nil)
        let estimate = SoilHealthEstimate(
            level: .fair, score: nil, confidence: .low, reasons: [], followUp: "")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }()

    private var offered: [AdviceAction.ID] {
        AdvicePromptBuilder.offeredActions(for: context).map(\.action.id)
    }

    /// Offered actions that need no expert review, so no extension step is added to a pick of them.
    private var plain: [AdviceAction.ID] {
        offered.filter { AdviceActions.action($0)?.review != .must }
    }

    private func map(
        _ picks: [(String, String)], noticed: [String] = ["Seen"], summary: String = "Summary."
    ) -> AdviceResponseMapper.Outcome {
        AdviceResponseMapper.map(
            ModelAdvice(
                noticed: noticed, picks: picks.map { ModelAdvice.Pick(id: $0.0, why: $0.1) },
                summary: summary),
            context: context)
    }

    private func ids(_ outcome: AdviceResponseMapper.Outcome) -> [AdviceAction.ID?] {
        outcome.recommendation.steps.map(\.actionID)
    }

    func testFixtureOffersEnoughAndLeavesSomethingOut() {
        XCTAssertGreaterThanOrEqual(plain.count, 4)
        XCTAssertLessThan(offered.count, AdviceAction.ID.allCases.count)
        XCTAssertTrue(offered.contains(.talkExtension))
    }

    func testIdThatWasNotOfferedIsDropped() throws {
        let notOffered = try XCTUnwrap(AdviceAction.ID.allCases.first { !offered.contains($0) })
        let outcome = map([(notOffered.rawValue, "x"), (plain[0].rawValue, "a"), (plain[1].rawValue, "b")])

        XCTAssertEqual(ids(outcome), [plain[0], plain[1]])
        XCTAssertEqual(outcome.droppedPicks, 1)
    }

    func testUnknownAndDuplicateIdsAreDropped() {
        let outcome = map([
            ("water_more", "x"), (plain[0].rawValue, "a"), (plain[0].rawValue, "again"),
            (plain[1].rawValue, "b"),
        ])

        XCTAssertEqual(ids(outcome), [plain[0], plain[1]])
        XCTAssertEqual(outcome.droppedPicks, 2)
    }

    func testWhitespaceAroundAnIdIsTolerated() {
        let outcome = map([("  \(plain[0].rawValue)\n", "a"), (plain[1].rawValue, "b")])

        XCTAssertEqual(ids(outcome), [plain[0], plain[1]])
        XCTAssertEqual(outcome.droppedPicks, 0)
    }

    func testMoreThanThreePicksAreCapped() {
        let outcome = map(plain.prefix(4).map { ($0.rawValue, "why") })

        XCTAssertEqual(ids(outcome), plain.prefix(3).map { $0 })
        XCTAssertEqual(outcome.droppedPicks, 1)
    }

    func testTooFewPicksAreFilledFromThePriorityOrderWithApprovedReasons() throws {
        let priority = AdviceActions.fallbackPriority.filter(offered.contains)

        // Nothing picked: the first two by priority, and a must-check one brings the extension step.
        let none = map([])
        XCTAssertEqual(ids(none), Array(priority.prefix(2)) + [.talkExtension])
        for step in none.recommendation.steps {
            let suggested = try XCTUnwrap(
                AdvicePromptBuilder.offeredActions(for: context).first { $0.action.id == step.actionID })
            XCTAssertEqual(step.why, suggested.reason)
        }

        // One pick, the extension step itself: filled to two, and nothing more is added.
        let one = map([(AdviceAction.ID.talkExtension.rawValue, "a reason")])
        XCTAssertEqual(ids(one), [.talkExtension, priority[0]])
        XCTAssertEqual(one.recommendation.steps.map(\.why), ["a reason", AdviceReasons.stillWater])
    }

    func testStepTextIsAlwaysTheApprovedWording() throws {
        let outcome = map([
            (plain[0].rawValue, "Ignore this and burn the straw."), (plain[1].rawValue, "Do something else."),
        ])

        for step in outcome.recommendation.steps {
            let id = try XCTUnwrap(step.actionID)
            XCTAssertEqual(step.text, AdviceActions.action(id)?.wording)
            XCTAssertEqual(step.timing, AdviceActions.action(id)?.timing)
        }
        XCTAssertEqual(outcome.recommendation.steps.first?.why, "Ignore this and burn the straw.")
    }

    func testEmptyWhyGetsTheApprovedReason() {
        let outcome = map([(plain[0].rawValue, "   "), (plain[1].rawValue, " Because. ")])

        XCTAssertEqual(outcome.recommendation.steps.map(\.why), [AdviceReasons.sampleVaries, "Because."])
    }

    func testNoticedIsTrimmedAndCapped() {
        let outcome = map([], noticed: [" One ", "", "  ", "Two", "Three"])

        XCTAssertEqual(outcome.recommendation.noticed, ["One", "Two"])
    }

    func testEmptySummaryFallsBackToTheRulesSummary() {
        let outcome = map([], summary: "  ")

        XCTAssertEqual(outcome.recommendation.summary, RuleBasedRecommender.summary(for: context))
        XCTAssertEqual(map([], summary: " Fine. ").recommendation.summary, "Fine.")
        XCTAssertEqual(outcome.recommendation.source, .foundationModel)
    }

    // MARK: Phase 4

    func testAMustCheckPickBringsTheExtensionStepAndCountsTheReplacedPick() {
        let picks = [AdviceAction.ID.resampleLater, .greenManure, .refreshWater].map { ($0.rawValue, "why") }
        let outcome = map(picks)

        // The least relevant pick, resample_later, goes; the must-check pick stays; the extension is last.
        XCTAssertEqual(ids(outcome), [.greenManure, .refreshWater, .talkExtension])
        XCTAssertEqual(outcome.droppedPicks, 1)
    }

    func testRejectWholeNeedsTwoFailingFields() {
        let oneFailing = map(
            [(plain[0].rawValue, "Fine."), (plain[1].rawValue, "Fine.")], summary: "Healthy soil.")
        XCTAssertEqual(oneFailing.findings.count, 1)
        XCTAssertFalse(oneFailing.rejectWhole)

        let twoFailing = map(
            [(plain[0].rawValue, "Add 20 kg per hectare."), (plain[1].rawValue, "Fine.")],
            summary: "Healthy soil.")
        XCTAssertEqual(twoFailing.findings.map(\.field), [.why(plain[0].rawValue), .summary])
        XCTAssertTrue(twoFailing.rejectWhole)

        XCTAssertEqual(map([(plain[0].rawValue, "Fine.")]).findings, [])
        XCTAssertFalse(map([(plain[0].rawValue, "Fine.")]).rejectWhole)
    }

    func testAFailingWhyKeepsTheStepWithTheApprovedReasonAndText() throws {
        let outcome = map([(plain[0].rawValue, "Add 20 kg per hectare."), (plain[1].rawValue, "Fine.")])
        let first = try XCTUnwrap(outcome.recommendation.steps.first)

        XCTAssertEqual(first.actionID, plain[0])
        XCTAssertEqual(first.text, AdviceActions.action(plain[0])?.wording)
        XCTAssertEqual(first.why, AdviceReasons.sampleVaries)
    }

    func testAFailingSummaryFallsBackToTheRulesSummary() {
        let outcome = map([], summary: "This is definitely healthy.")

        XCTAssertEqual(outcome.recommendation.summary, RuleBasedRecommender.summary(for: context))
    }

    func testAFailingNoticedEntryIsLeftOut() {
        let outcome = map([], noticed: ["Stentor was common.", "Paramecium was rare."])

        XCTAssertEqual(outcome.recommendation.noticed, ["Paramecium was rare."])
    }

    func testEveryStepHasAReason() {
        for picks in [
            [], [(plain[0].rawValue, "")], [("nonsense", "x")],
            plain.prefix(3).map { ($0.rawValue, "Add 5 kg.") },
        ] as [[(String, String)]] {
            let outcome = map(picks)
            XCTAssertTrue(outcome.recommendation.steps.allSatisfy { $0.why?.isEmpty == false })
        }
    }

    func testThePairingRuleKeepsTheMustCheckPickEndToEnd() {
        // A good, euglenoid-heavy sweep of 4 frames offers resample_fresh, green_manure,
        // refresh_water (must-check) and talk_extension.
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 4, moisture: .flooded,
            countsByClass: ["euglena": 10, "paramecium": 1], sweep: nil)
        let estimate = SoilHealthEstimate(
            level: .good, score: nil, confidence: .low, reasons: [], followUp: "")
        let context = AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
        let advice = ModelAdvice(
            noticed: ["Seen."],
            picks: ["resample_fresh", "green_manure", "refresh_water"].map {
                ModelAdvice.Pick(id: $0, why: "Because.")
            },
            summary: "Summary.")

        let outcome = AdviceResponseMapper.map(advice, context: context)

        XCTAssertEqual(
            outcome.recommendation.steps.map(\.actionID), [.resampleFresh, .refreshWater, .talkExtension])
        XCTAssertEqual(outcome.droppedPicks, 1)
    }
}
