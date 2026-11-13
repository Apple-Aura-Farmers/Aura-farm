import XCTest

@testable import AuraFarm

final class AdvicePromptBuilderTests: XCTestCase {
    private func context(
        _ counts: [String: Int],
        level: SoilHealthEstimate.Level = .fair,
        frames: Int = 10,
        moisture: SampleDetails.Moisture = .flooded,
        stage: SampleDetails.CropStage? = nil,
        recent: [SampleDetails.RecentAction] = [],
        stoppedEarly: Bool = false,
        history: [PastResult] = [],
        soil: SoilMeasurements? = nil
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: frames, moisture: moisture, countsByClass: counts,
            sweep: nil, cropStage: stage, recentActions: recent, stoppedEarly: stoppedEarly, soil: soil)
        let estimate = SoilHealthEstimate(
            level: level, score: nil, confidence: .low, reasons: [], followUp: "Test again.")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: history)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))
            ?? .distantPast
    }

    func testAlsoSeenOrganismsAppearOnlyOnTheAlsoSeenLine() {
        let prompt = AdvicePromptBuilder.prompt(for: context(["Paramecium": 10, "Stentor": 6, "Volvox": 1]))
        let mentions = prompt.split(separator: "\n").filter {
            $0.contains("Stentor") || $0.contains("Volvox")
        }

        XCTAssertEqual(mentions, ["Also seen (do not interpret or mention): Stentor 6, Volvox 1."])
    }

    func testPyrocystisIsNeverAnOrganismSeen() {
        let prompt = AdvicePromptBuilder.prompt(
            for: context(["Pyrocystis": 10, "Paramecium": 12, "Euglena": 6]))

        XCTAssertFalse(prompt.contains("- Pyrocystis"))
        XCTAssertTrue(prompt.contains("Also seen (do not interpret or mention): Pyrocystis 10."))
    }

    func testEmptySectionsAreLeftOut() {
        let prompt = AdvicePromptBuilder.prompt(for: context(["paramecium": 20, "amoeba": 20], level: .good))

        for header in [
            "Crop stage:", "Done recently:", "Cautions:", "Also seen", "Patterns:", "Earlier samples",
        ] {
            XCTAssertFalse(prompt.contains(header), header)
        }
        XCTAssertTrue(prompt.contains("Organisms seen:"))
        XCTAssertTrue(prompt.hasSuffix("Write the advice."))
    }

    func testOnlyTypicalOrSilentLowCountsGoWithoutANote() {
        // 0.2 per frame over 20 frames: a low worth reading. Paramecium's low note is worth
        // saying, Euglena's is "Normal".
        let prompt = AdvicePromptBuilder.prompt(
            for: context(["paramecium": 4, "euglena": 4, "vorticella": 60], frames: 20))

        XCTAssertTrue(
            prompt.contains("- Paramecium: 4 (0.2 per frame, low). Might suggest: Little organic matter"))
        XCTAssertTrue(prompt.contains("- Euglena: 4 (0.2 per frame, low).\n"))
        XCTAssertTrue(prompt.contains("- Vorticella: 60 (3.0 per frame, high). Might suggest: Enough oxygen"))
    }

    func testLowCountInAShortSweepIsOnlyFewSeen() {
        let prompt = AdvicePromptBuilder.prompt(
            for: context(["paramecium": 2, "vorticella": 30], frames: 12))

        XCTAssertTrue(prompt.contains("- Paramecium: 2 (0.2 per frame, few seen).\n"))
        XCTAssertFalse(prompt.contains("Little organic matter"))
    }

    func testEstimateLineSaysItIsFromTheAmountOfLifeOnly() {
        let prompt = AdvicePromptBuilder.prompt(for: context(["paramecium": 9], level: .good))

        XCTAssertTrue(
            prompt.contains("\nRough estimate from the amount of life only: good, low confidence.\n"))
    }

    func testThisSampleLineMatchesTheHistoryLines() {
        let prompt = AdvicePromptBuilder.prompt(
            for: context(["paramecium": 9, "euglena": 6, "stentor": 4], frames: 10))
        let lines = prompt.split(separator: "\n")

        XCTAssertEqual(lines[2], "This sample: 1.5 per frame, 2 kinds.")
        XCTAssertTrue(lines[1].hasPrefix("Rough estimate"))
        XCTAssertFalse(AdvicePromptBuilder.prompt(for: context(["stentor": 6])).contains("This sample:"))
    }

    func testOfferedActionsAreTheActionsInThePrompt() {
        let context = context(["euglena": 30, "nematode": 30, "paramecium": 1], level: .poor, frames: 12)
        let prompt = AdvicePromptBuilder.prompt(for: context)
        let listed = AdviceAction.ID.allCases.filter { prompt.contains("- \($0.rawValue): ") }

        XCTAssertEqual(AdvicePromptBuilder.offeredActions(for: context).map(\.action.id), listed)
        XCTAssertEqual(
            AdvicePromptBuilder.offeredActions(for: context),
            AdvicePromptBuilder.trimmed(context.actions, context: context))
    }

    /// A context whose actions are all given, so trimming can be tried on any list.
    private func contextWith(
        _ ids: [AdviceAction.ID], level: SoilHealthEstimate.Level = .fair
    ) -> AdviceContext {
        var context = context(["paramecium": 5], level: level)
        context.actions = ids.compactMap { AdviceActions.action($0) }.map {
            AdviceContext.SuggestedAction(action: $0, because: "test", reason: "Reason.")
        }
        return context
    }

    private func trimmedIDs(_ context: AdviceContext) -> [AdviceAction.ID] {
        AdvicePromptBuilder.trimmed(context.actions, context: context).map(\.action.id)
    }

    func testActionsAreTrimmedToTheSixMostRelevantInCatalogueOrder() {
        let context = contextWith(AdviceAction.ID.allCases)

        // Fresh, trust and (for a fair result) later are never dropped. A must-check action
        // survives, so talk_extension is kept too; the rest fill the room by priority.
        XCTAssertEqual(
            trimmedIDs(context),
            [.resampleFresh, .resampleFlooded, .resampleLater, .resampleTrust, .refreshWater, .talkExtension])

        let prompt = AdvicePromptBuilder.prompt(for: context)
        let listed = AdviceAction.ID.allCases.filter { prompt.contains("- \($0.rawValue): ") }
        XCTAssertEqual(listed, trimmedIDs(context))
    }

    func testTrimmingDropsNotesFirstAndLeavesShortListsAlone() {
        let seven: [AdviceAction.ID] = [
            .resampleFresh, .resampleFlooded, .resampleLater, .resampleTrust, .keepPractice, .returnStraw,
            .keepNotes,
        ]
        let kept = trimmedIDs(contextWith(seven))

        XCTAssertEqual(kept.count, 6)
        XCTAssertFalse(kept.contains(.keepNotes))
        XCTAssertEqual(trimmedIDs(contextWith(Array(AdviceAction.ID.allCases.prefix(6)))).count, 6)
    }

    func testSamplingAgainIsProtectedForFairAndPoorButNotGoodResults() {
        let all = AdviceAction.ID.allCases
        XCTAssertTrue(trimmedIDs(contextWith(all, level: .fair)).contains(.resampleLater))
        XCTAssertTrue(trimmedIDs(contextWith(all, level: .poor)).contains(.resampleLater))
        XCTAssertFalse(trimmedIDs(contextWith(all, level: .good)).contains(.resampleLater))
    }

    func testTalkExtensionIsProtectedOnlyWhenNeeded() {
        let withoutMust: [AdviceAction.ID] = [
            .resampleFresh, .resampleFlooded, .resampleLater, .resampleTrust, .keepPractice, .stopBurning,
            .greenManure, .reviewFertilizer, .checkRootPests, .talkExtension, .labTest, .keepNotes,
        ]
        // Fair, and nothing that needs an expert survives: it is trimmed like any other.
        XCTAssertFalse(trimmedIDs(contextWith(withoutMust, level: .fair)).contains(.talkExtension))
        // A poor result always keeps it.
        let poor = trimmedIDs(contextWith(withoutMust, level: .poor))
        XCTAssertTrue(poor.contains(.talkExtension))
        XCTAssertEqual(poor.count, 6)
        // A must-check action that survives brings it too.
        XCTAssertTrue(
            trimmedIDs(contextWith(AdviceAction.ID.allCases, level: .fair)).contains(.talkExtension))
    }

    func testPoorEuglenaOnlySampleKeepsTheActionsThatFitIt() {
        let ids = AdvicePromptBuilder.offeredActions(
            for: context(["euglena": 7], level: .poor, frames: 30)
        ).map(\.action.id)

        XCTAssertTrue(ids.contains(.refreshWater))
        XCTAssertTrue(ids.contains(.reviewFertilizer))
        XCTAssertTrue(ids.contains(.talkExtension))
        XCTAssertTrue(ids.contains(.resampleLater))
        XCTAssertFalse(ids.contains(.addCompost))
        XCTAssertFalse(ids.contains(.returnStraw))
        XCTAssertLessThanOrEqual(ids.count, 6)
    }

    func testActionLinesGiveTheReasonNotTheInternalLabel() {
        let context = context(["euglena": 10, "paramecium": 1])
        let prompt = AdvicePromptBuilder.prompt(for: context)

        XCTAssertTrue(
            prompt.contains(
                "- refresh_water: \"\(AdviceActions.action(.refreshWater)?.wording ?? "")\" "
                    + "(why: \(AdviceReasons.stillWater); timing: this week)"))
        XCTAssertFalse(prompt.contains("because"))
    }

    func testFewActionsAreAllListed() {
        let context = context(["paramecium": 20, "amoeba": 20], level: .good)
        let prompt = AdvicePromptBuilder.prompt(for: context)

        for action in context.actions {
            XCTAssertTrue(prompt.contains("- \(action.action.id.rawValue): \"\(action.action.wording)\""))
        }
    }

    func testHistoryLines() {
        let history = [
            PastResult(
                recordedAt: date(2026, 10, 12), moisture: .flooded, cropStage: .tillering,
                organismsPerFrame: 1.1, interpretedKinds: 3, level: .fair),
            PastResult(
                recordedAt: date(2026, 9, 2), moisture: .drained, cropStage: nil, organismsPerFrame: 0.46,
                interpretedKinds: 1, level: .poor),
        ]
        let prompt = AdvicePromptBuilder.prompt(for: context(["paramecium": 9], history: history))

        XCTAssertTrue(
            prompt.contains(
                "Earlier samples of this plot:\n"
                    + "- 12 Oct 2026, flooded, tillering: 1.1 per frame, 3 kinds, fair.\n"
                    + "- 2 Sep 2026, drained: 0.5 per frame, 1 kind, poor."))
    }

    /// The on-device model's context window is 4,096 tokens, and it must hold the
    /// instructions, the prompt and the answer. English runs at roughly 3 to 4 characters a
    /// token, so 7,000 characters of input leaves room for a short answer. A rough proxy,
    /// not a token count.
    func testWorstCaseStaysWithinTheBudget() {
        let labels = OrganismNotes.all.map(\.label)
        var counts = Dictionary(uniqueKeysWithValues: labels.map { ($0, 40) })
        counts["paramecium"] = 1  // Low, so Didinium has little prey.
        counts["pyrocystis"] = 400  // A large share, so the labels look off.
        let history = (1...3).map { index in
            PastResult(
                recordedAt: date(2026, 9, index), moisture: .drained, cropStage: .tillering,
                organismsPerFrame: 0.4, interpretedKinds: 2, level: .poor)
        }
        let context = context(
            counts, level: .poor, frames: 3, moisture: .drained, stage: .ripening,
            recent: SampleDetails.RecentAction.allCases, stoppedEarly: true, history: history)

        let prompt = AdvicePromptBuilder.prompt(for: context)
        let total = AdvicePromptBuilder.instructions().count + prompt.count

        XCTAssertGreaterThan(context.patterns.count, 5)
        XCTAssertLessThan(total, 7_000, "Instructions plus prompt are \(total) characters")
        XCTAssertFalse(prompt.lowercased().contains("healthy"))
    }

    // MARK: Soil measurements

    private let fullSoil = SoilMeasurements(
        nitrogen: 100, ph: 7.9, organicCarbonPercent: 2.5, fertilizerProduct: "Urea",
        fertilizerKilogramsPerHectare: 50)

    func testSoilMeasurementsAreOneBackgroundLineAfterTheSampleLines() {
        let prompt = AdvicePromptBuilder.prompt(
            for: context(["paramecium": 9, "euglena": 6], soil: fullSoil))
        let lines = prompt.split(separator: "\n")

        XCTAssertEqual(
            lines[3],
            "Soil measurements the helper recorded (not from the microscope; background only, do not "
                + "give advice from them): nitrogen 100 mg/kg (standard), pH 7.9 (excessive), "
                + "organic carbon 2.5 % (standard).")
        XCTAssertTrue(lines[2].hasPrefix("This sample:"))
        XCTAssertEqual(prompt.components(separatedBy: "Soil measurements").count, 2)
    }

    func testTheStandardsGuidanceAndTheFertilizerNeverReachThePrompt() {
        let prompt = AdvicePromptBuilder.prompt(
            for: context(["paramecium": 9, "euglena": 6], soil: fullSoil))

        XCTAssertFalse(prompt.contains("Urea"))
        XCTAssertFalse(prompt.contains("kg per"))
        XCTAssertFalse(prompt.contains("Maintain it"))
        XCTAssertFalse(prompt.contains("zinc"))
    }

    func testWithoutReadableMeasurementsThePromptIsExactlyWhatItWas() {
        let counts = ["paramecium": 9, "euglena": 6]
        let plain = AdvicePromptBuilder.prompt(for: context(counts))

        XCTAssertFalse(plain.contains("Soil measurements"))
        XCTAssertEqual(plain, AdvicePromptBuilder.prompt(for: context(counts, soil: nil)))
        XCTAssertEqual(plain, AdvicePromptBuilder.prompt(for: context(counts, soil: SoilMeasurements())))
        XCTAssertEqual(
            plain,
            AdvicePromptBuilder.prompt(
                for: context(
                    counts,
                    soil: SoilMeasurements(fertilizerProduct: "Urea", fertilizerKilogramsPerHectare: 50))))
    }

    func testMeasurementsDoNotChangeTheEstimatePatternsOrActions() {
        let counts = ["euglena": 30, "phacus": 8, "paramecium": 3]
        let without = context(counts, level: .poor, stage: .tillering)
        let with = context(counts, level: .poor, stage: .tillering, soil: fullSoil)

        XCTAssertEqual(with.estimate, without.estimate)
        XCTAssertEqual(with.patterns, without.patterns)
        XCTAssertEqual(with.actions, without.actions)
        XCTAssertEqual(with.cautions, without.cautions)
        XCTAssertEqual(
            AdvicePromptBuilder.offeredActions(for: with).map(\.action.id),
            AdvicePromptBuilder.offeredActions(for: without).map(\.action.id))
    }

    func testTheSoilLineIsSmallEnoughNotToThreatenTheBudget() {
        let all = SoilMeasurements(
            nitrogen: 100.55, phosphorus: 20.25, potassium: 150.75, ph: 6.55, organicCarbonPercent: 2.55)
        let counts = ["paramecium": 9, "euglena": 6]

        let extra =
            AdvicePromptBuilder.prompt(for: context(counts, soil: all)).count
            - AdvicePromptBuilder.prompt(for: context(counts)).count

        XCTAssertLessThan(extra, 400, "The soil line adds \(extra) characters")
    }

    func testNumbersAreWrittenTheSameOnEveryPhone() {
        let soil = SoilMeasurements(nitrogen: 1_000, ph: 6.55)
        let prompt = AdvicePromptBuilder.prompt(for: context(["paramecium": 9], soil: soil))

        XCTAssertTrue(prompt.contains("nitrogen 1000 mg/kg"))
        XCTAssertTrue(prompt.contains("pH 6.55 (standard)"))
    }

    func testInstructionsCarryTheNeverSayRules() {
        let instructions = AdvicePromptBuilder.instructions()

        for rule in NeverSay.rules {
            XCTAssertTrue(instructions.contains(rule), rule)
        }
        XCTAssertTrue(
            instructions.contains(
                "The rough estimate only reflects how much life was seen. If a pattern raises a concern, do not "
                    + "describe the result as good."))
        XCTAssertTrue(
            instructions.contains("Pick 2 or 3 actions from \"Actions you may suggest\" by their id."))
        XCTAssertTrue(instructions.contains("Do not repeat the action's wording."))
        XCTAssertTrue(instructions.contains("First note 1 or 2 things you noticed"))
        XCTAssertFalse(instructions.contains("Choose 2 or 3 actions"))
        XCTAssertTrue(instructions.contains("building on the reason given"))
    }
}
