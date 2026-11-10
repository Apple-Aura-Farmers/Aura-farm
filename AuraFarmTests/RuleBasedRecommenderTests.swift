import XCTest

@testable import AuraFarm

final class RuleBasedRecommenderTests: XCTestCase {
    private func context(
        _ counts: [String: Int]?, level: SoilHealthEstimate.Level, frames: Int = 10
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: frames, moisture: .flooded, countsByClass: counts,
            sweep: nil)
        let estimate = SoilHealthEstimate(
            level: level, score: nil, confidence: .low, reasons: [], followUp: "")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }

    func testNotCountedGetsTheTwoFixedSteps() {
        let recommendation = RuleBasedRecommender.recommendation(for: context(nil, level: .notCounted))

        XCTAssertEqual(
            recommendation.steps.map(\.text),
            ["Run the sweep again.", "If counting keeps failing, restart the app."])
        XCTAssertTrue(recommendation.steps.allSatisfy { $0.actionID == nil && $0.timing == nil })
        XCTAssertEqual(
            recommendation.steps.map(\.why),
            Array(repeating: "Counting didn't run on this sweep.", count: 2))
        XCTAssertEqual(recommendation.source, .rules)
        XCTAssertEqual(recommendation.noticed, [])
    }

    func testOtherLevelsPickOfferedActionsWithTheirApprovedReasons() throws {
        for (counts, level) in [
            (["euglena": 10, "paramecium": 1], SoilHealthEstimate.Level.fair),
            (["paramecium": 20, "amoeba": 20, "vorticella": 20], .good),
            (["paramecium": 5, "amoeba": 2], .poor),
            ([:], .tooFewToSay),
        ] {
            let context = context(counts, level: level)
            let steps = RuleBasedRecommender.recommendation(for: context).steps
            let offered = AdvicePromptBuilder.offeredActions(for: context)

            XCTAssertTrue((2...3).contains(steps.count), "\(level): \(steps.count) steps")
            for step in steps {
                let suggested = try XCTUnwrap(offered.first { $0.action.id == step.actionID }, "\(level)")
                XCTAssertEqual(step.text, suggested.action.wording)
                XCTAssertEqual(step.why, suggested.reason)
                XCTAssertEqual(step.timing, suggested.action.timing)
            }
            // Priority order, apart from an extension step added at the end for a must-check action.
            let order = steps.compactMap(\.actionID).filter { $0 != .talkExtension }
                .map { AdviceActions.fallbackPriority.firstIndex(of: $0) ?? -1 }
            XCTAssertEqual(order, order.sorted(), "\(level)")
        }
    }

    func testStepsFollowThePriorityOrderWhenNothingNeedsAnExpert() {
        let context = context(["paramecium": 20, "amoeba": 20, "vorticella": 20], level: .good)
        let steps = RuleBasedRecommender.recommendation(for: context).steps

        XCTAssertEqual(steps.map(\.actionID), [.keepPractice, .keepNotes])
    }

    func testAMustCheckStepAlwaysComesWithTheExtensionStep() {
        let steps = RuleBasedRecommender.recommendation(
            for: context(["euglena": 10, "paramecium": 1], level: .fair)
        ).steps

        XCTAssertTrue(steps.contains { $0.actionID == .talkExtension })
        XCTAssertLessThanOrEqual(steps.count, 3)
    }

    func testBlockedSampleIsHardToRead() {
        let summary = RuleBasedRecommender.summary(
            for: context(["pyrocystis": 10, "paramecium": 12], level: .fair))

        XCTAssertEqual(summary, "This sample is hard to read. Check it again before changing anything.")
    }

    func testConcernSampleIsWorthACloserLook() {
        let summary = RuleBasedRecommender.summary(
            for: context(["nematode": 30, "paramecium": 20, "amoeba": 20], level: .good))

        XCTAssertEqual(summary, "Some of what was seen is worth a closer look.")
    }

    func testOrdinarySampleKeepsItsLevelSummary() {
        let summary = RuleBasedRecommender.summary(
            for: context(["paramecium": 20, "amoeba": 20, "vorticella": 20], level: .good))

        XCTAssertEqual(summary, "Plenty of soil life was seen. Keep doing what is working.")
    }

    func testNoSummaryUsesABannedWord() {
        let contexts =
            SoilHealthEstimate.Level.allCases.map { context(["paramecium": 20, "amoeba": 20], level: $0) } + [
                context(["pyrocystis": 10, "paramecium": 12], level: .fair),
                context(["nematode": 30, "paramecium": 20], level: .good),
            ]
        for context in contexts {
            let summary = RuleBasedRecommender.summary(for: context).lowercased()
            for word in NeverSay.bannedWords {
                XCTAssertFalse(summary.contains(word), summary)
            }
        }
    }
}
