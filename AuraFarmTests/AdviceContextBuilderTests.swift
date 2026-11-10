import XCTest

@testable import AuraFarm

final class AdviceContextBuilderTests: XCTestCase {
    // Ten frames, so a count of 21 is 2.1 per frame.
    private func context(
        _ counts: [String: Int]?,
        level: SoilHealthEstimate.Level = .fair,
        frames: Int = 10,
        moisture: SampleDetails.Moisture = .flooded,
        stage: SampleDetails.CropStage? = nil,
        recent: [SampleDetails.RecentAction] = [],
        stoppedEarly: Bool = false,
        history: [PastResult] = []
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: frames, moisture: moisture, countsByClass: counts,
            sweep: nil, cropStage: stage, recentActions: recent, stoppedEarly: stoppedEarly)
        let estimate = SoilHealthEstimate(
            level: level, score: nil, confidence: .low, reasons: [], followUp: "Test again.")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: history)
    }

    private func patterns(
        _ counts: [String: Int], level: SoilHealthEstimate.Level = .fair,
        moisture: SampleDetails.Moisture = .flooded
    ) -> [AdvicePattern] {
        context(counts, level: level, moisture: moisture).patterns
    }

    private func actions(_ context: AdviceContext) -> [AdviceAction.ID] {
        context.actions.map(\.action.id)
    }

    private func past(_ level: SoilHealthEstimate.Level) -> PastResult {
        PastResult(
            recordedAt: .distantPast, moisture: .flooded, cropStage: nil, organismsPerFrame: 1,
            interpretedKinds: 2, level: level)
    }

    // MARK: Readings

    func testReviewPileAndUnknownLabelsAreOnlyAlsoSeen() {
        let context = context(["Paramecium": 5, "Stentor": 3, "Rotifer": 2, "Pyrocystis": 1, "volvox": 0])

        XCTAssertEqual(context.interpreted.map(\.note.label), ["paramecium"])
        XCTAssertEqual(context.alsoSeen.map(\.displayName), ["Stentor", "Rotifer", "Pyrocystis"])
    }

    func testReadingsAreMergedAcrossCaseAndSortedMostCountedFirst() {
        let context = context(["Euglena": 3, "euglena": 2, "Paramecium": 9])

        XCTAssertEqual(context.interpreted.map(\.note.label), ["paramecium", "euglena"])
        XCTAssertEqual(context.interpreted.last?.count, 5)
        XCTAssertEqual(context.interpreted.last?.perFrame, 0.5)
    }

    // MARK: Patterns

    func testSeveralRoles() {
        XCTAssertTrue(patterns(["paramecium": 5, "didinium": 1, "euglena": 5]).contains(.severalRoles))
        XCTAssertFalse(patterns(["paramecium": 5, "euglena": 5]).contains(.severalRoles))
    }

    func testEuglenoidsDominant() {
        XCTAssertTrue(patterns(["euglena": 10, "paramecium": 1]).contains(.euglenoidsDominant))
        XCTAssertFalse(patterns(["euglena": 10, "paramecium": 3]).contains(.euglenoidsDominant))
    }

    func testCleanWaterAlgae() {
        XCTAssertTrue(patterns(["dinobryon": 1, "paramecium": 10]).contains(.cleanWaterAlgae))
        XCTAssertFalse(patterns(["dinobryon": 1, "paramecium": 5, "euglena": 2]).contains(.cleanWaterAlgae))
    }

    func testMixedSignalsSuppressesBothReadings() {
        let mixed = patterns(["euglena": 30, "dinobryon": 1])
        XCTAssertTrue(mixed.contains(.mixedSignals))
        XCTAssertFalse(mixed.contains(.euglenoidsDominant))
        XCTAssertFalse(mixed.contains(.cleanWaterAlgae))

        let notHigh = patterns(["euglena": 15, "dinobryon": 1])
        XCTAssertFalse(notHigh.contains(.mixedSignals))
        XCTAssertTrue(notHigh.contains(.euglenoidsDominant))
    }

    func testPredatorWithLowPrey() {
        XCTAssertTrue(patterns(["didinium": 1, "paramecium": 2]).contains(.predatorWithLowPrey))
        XCTAssertTrue(patterns(["didinium": 1, "vorticella": 5]).contains(.predatorWithLowPrey))
        XCTAssertFalse(patterns(["didinium": 1, "paramecium": 5]).contains(.predatorWithLowPrey))
    }

    func testPlentyOfVorticella() {
        XCTAssertTrue(patterns(["vorticella": 21]).contains(.plentyOfVorticella))
        XCTAssertFalse(patterns(["vorticella": 20]).contains(.plentyOfVorticella))
    }

    func testPlentyOfTestateAmoebae() {
        XCTAssertTrue(patterns(["arcellinida": 11]).contains(.plentyOfTestateAmoebae))
        XCTAssertFalse(patterns(["arcellinida": 10]).contains(.plentyOfTestateAmoebae))
    }

    func testNematodesHigh() {
        XCTAssertTrue(patterns(["Nematoda": 21]).contains(.nematodesHigh))
        XCTAssertFalse(patterns(["nematode": 20]).contains(.nematodesHigh))
    }

    func testDrainedLowCounts() {
        XCTAssertTrue(
            patterns(["paramecium": 5], level: .poor, moisture: .drained).contains(.drainedLowCounts))
        XCTAssertFalse(
            patterns(["paramecium": 5], level: .good, moisture: .drained).contains(.drainedLowCounts))
        XCTAssertFalse(
            patterns(["paramecium": 5], level: .fair, moisture: .flooded).contains(.drainedLowCounts))
    }

    func testOnlyOneKindCountsInterpretedKindsOnly() {
        XCTAssertTrue(patterns(["paramecium": 5, "stentor": 3]).contains(.onlyOneKind))
        XCTAssertFalse(patterns(["paramecium": 5, "euglena": 1]).contains(.onlyOneKind))
    }

    func testNothingInterpretable() {
        XCTAssertTrue(patterns(["stentor": 5]).contains(.nothingInterpretable))
        XCTAssertFalse(patterns([:]).contains(.nothingInterpretable))
    }

    func testPossibleMisidentification() {
        let context = context(["pyrocystis": 2, "paramecium": 8])
        XCTAssertTrue(context.patterns.contains(.possibleMisidentification))
        XCTAssertTrue(context.cautions.contains("Some organisms may have been misidentified."))
        XCTAssertTrue(actions(context).contains(.resampleTrust))
        XCTAssertFalse(patterns(["pyrocystis": 1, "paramecium": 8]).contains(.possibleMisidentification))
    }

    // MARK: Actions

    func testReturnStrawExclusions() {
        XCTAssertTrue(actions(context(["paramecium": 5])).contains(.returnStraw))
        XCTAssertFalse(actions(context(["euglena": 30, "paramecium": 1])).contains(.returnStraw))
        XCTAssertFalse(actions(context(["paramecium": 5], stage: .seedling)).contains(.returnStraw))
        XCTAssertFalse(actions(context(["paramecium": 5], recent: [.addedStraw])).contains(.returnStraw))
    }

    func testAddCompostIsBlockedByCleanWaterAlgae() {
        XCTAssertTrue(actions(context(["paramecium": 5])).contains(.addCompost))
        XCTAssertFalse(actions(context(["dinobryon": 1, "paramecium": 5])).contains(.addCompost))
        XCTAssertFalse(actions(context(["paramecium": 5], recent: [.addedCompost])).contains(.addCompost))
    }

    func testGreenManureIsBlockedMidSeason() {
        XCTAssertTrue(actions(context(["paramecium": 5], stage: .fallow)).contains(.greenManure))
        for stage in [SampleDetails.CropStage.seedling, .tillering, .flowering] {
            XCTAssertFalse(
                actions(context(["paramecium": 5], stage: stage)).contains(.greenManure), "\(stage)")
        }
    }

    func testAlternateWetDryExclusions() {
        let dominant = ["euglena": 10, "paramecium": 1]
        XCTAssertTrue(actions(context(dominant)).contains(.alternateWetDry))
        XCTAssertFalse(actions(context(dominant, stage: .flowering)).contains(.alternateWetDry))
        XCTAssertFalse(actions(context(dominant, moisture: .drained)).contains(.alternateWetDry))
        XCTAssertFalse(actions(context(dominant, recent: [.drained])).contains(.alternateWetDry))
    }

    func testReviewFertilizerMentionsRecentFertilizing() {
        let context = context(["euglena": 10, "paramecium": 1], recent: [.fertilized])
        let action = context.actions.first { $0.action.id == .reviewFertilizer }
        XCTAssertEqual(action?.because, "euglenoids dominant, fertilized recently")
    }

    func testTalkExtensionFollowsAMustCheckAction() {
        XCTAssertTrue(actions(context(["euglena": 10, "paramecium": 1])).contains(.talkExtension))
        let plenty = context(["paramecium": 20, "vorticella": 20, "amoeba": 20], level: .good)
        XCTAssertFalse(actions(plenty).contains(.talkExtension))
        XCTAssertTrue(
            actions(context(["paramecium": 20, "amoeba": 20], level: .poor)).contains(.talkExtension))
    }

    func testKeepPracticeOnlyForAGoodResult() {
        XCTAssertTrue(
            actions(context(["paramecium": 20, "amoeba": 20], level: .good)).contains(.keepPractice))
        XCTAssertFalse(actions(context(["paramecium": 20], level: .poor)).contains(.keepPractice))
    }

    func testLabTestNeedsAPoorEarlierResult() {
        XCTAssertTrue(
            actions(context(["paramecium": 5], level: .poor, history: [past(.poor)])).contains(.labTest))
        XCTAssertFalse(
            actions(context(["paramecium": 5], level: .poor, history: [past(.fair)])).contains(.labTest))
        XCTAssertFalse(actions(context(["paramecium": 5], level: .poor)).contains(.labTest))
        XCTAssertFalse(
            actions(context(["paramecium": 5], level: .fair, history: [past(.poor)])).contains(.labTest))
    }

    func testShortOrStoppedSweepAsksForAFreshSlide() {
        let context = context(["paramecium": 5, "euglena": 5], frames: 3, stoppedEarly: true)
        XCTAssertTrue(actions(context).contains(.resampleFresh))
        XCTAssertEqual(context.cautions, ["The sweep stopped early.", "Only a few frames were kept."])
    }

    func testOtherLevelsStillBuild() {
        XCTAssertTrue(actions(context([:], level: .tooFewToSay)).contains(.resampleFresh))
        let notCounted = context(nil, level: .notCounted)
        XCTAssertTrue(notCounted.interpreted.isEmpty)
        XCTAssertTrue(notCounted.patterns.isEmpty)
        XCTAssertTrue(actions(notCounted).contains(.keepNotes))
    }

    func testKeepNotesIsAlwaysThere() {
        for counts in [nil, [:], ["paramecium": 5], ["euglena": 30, "dinobryon": 1]] as [[String: Int]?] {
            XCTAssertTrue(actions(context(counts)).contains(.keepNotes))
        }
    }

    func testOrderIsStable() {
        let context = context(
            ["euglena": 30, "nematode": 30, "pyrocystis": 20], level: .poor, moisture: .drained)
        let ids = actions(context)
        XCTAssertEqual(ids, AdviceAction.ID.allCases.filter(ids.contains))
        XCTAssertEqual(context.patterns, AdvicePattern.allCases.filter(context.patterns.contains))
    }

    // MARK: Phase 3 fixes

    private func estimated(
        _ counts: [String: Int], frames: Int = 12
    ) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: frames, moisture: .flooded, countsByClass: counts,
            sweep: nil)
        return AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result), history: [])
    }

    private let resampleOrNotes: Set<AdviceAction.ID> = [
        .resampleFresh, .resampleFlooded, .resampleLater, .resampleTrust, .keepNotes,
    ]

    func testKeepPracticeIsNotOfferedBesideEuglenoidsDominant() {
        let context = estimated(["Euglena": 30, "Phacus": 8, "Paramecium": 3])

        XCTAssertEqual(context.estimate.level, .good)
        XCTAssertTrue(context.patterns.contains(.euglenoidsDominant))
        XCTAssertFalse(actions(context).contains(.keepPractice))
    }

    func testKeepPracticeIsNotOfferedWithAHighEuglenoidOrAnyConcern() {
        // Euglena high but not dominant, because ciliates are a large share.
        let high = context(["euglena": 30, "paramecium": 20, "vorticella": 20], level: .good)
        XCTAssertFalse(high.patterns.contains(.euglenoidsDominant))
        XCTAssertFalse(actions(high).contains(.keepPractice))

        let concerns: [AdvicePattern: [String: Int]] = [
            .euglenoidsDominant: ["euglena": 15, "paramecium": 1],
            .mixedSignals: ["euglena": 30, "dinobryon": 1],
            .nematodesHigh: ["nematode": 30, "paramecium": 20, "amoeba": 20],
            .possibleMisidentification: ["pyrocystis": 10, "paramecium": 20, "amoeba": 20],
            .nothingInterpretable: ["stentor": 30],
            .onlyOneKind: ["paramecium": 30],
        ]
        for pattern in AdvicePattern.allCases where pattern.isConcern {
            let counts = concerns[pattern] ?? [:]
            let context = context(counts, level: .good)
            XCTAssertTrue(context.patterns.contains(pattern), "\(pattern)")
            XCTAssertFalse(actions(context).contains(.keepPractice), "\(pattern)")
        }
        XCTAssertEqual(concerns.count, AdvicePattern.allCases.filter(\.isConcern).count)
    }

    func testUntrustworthySamplesOnlyOfferResamplingAndNotes() {
        let samples: [(AdvicePattern, [String: Int])] = [
            (.possibleMisidentification, ["Pyrocystis": 10, "Paramecium": 12, "Euglena": 6]),
            (.nothingInterpretable, ["Stentor": 6, "Volvox": 5, "Closterium": 3]),
            (.mixedSignals, ["Euglena": 40, "Dinobryon": 3, "Paramecium": 6]),
        ]
        for (pattern, counts) in samples {
            let context = estimated(counts)
            XCTAssertTrue(context.patterns.contains(pattern), "\(pattern)")
            XCTAssertTrue(
                Set(actions(context)).isSubset(of: resampleOrNotes), "\(pattern): \(actions(context))")
            XCTAssertTrue(actions(context).contains(.keepNotes))
        }
    }

    func testNothingReadableIsNotLowAbundance() {
        let ids = actions(context(["stentor": 6, "volvox": 5, "closterium": 3]))

        for id in [AdviceAction.ID.returnStraw, .addCompost, .stopBurning, .greenManure] {
            XCTAssertFalse(ids.contains(id), "\(id)")
        }
    }

    func testHighNeedsEnoughOrganisms() {
        // 1 per frame is high for a scarce organism, but 2 is too few to call high.
        XCTAssertEqual(context(["didinium": 2], frames: 2).interpreted.first?.band, .typical)
        XCTAssertEqual(context(["didinium": 3], frames: 3).interpreted.first?.band, .high)
    }

    func testLowOnlyMeansSomethingOverEnoughFrames() {
        let short = context(["paramecium": 2, "vorticella": 30], frames: 12).interpreted
        XCTAssertEqual(short.last?.band, .low)
        XCTAssertEqual(short.last?.lowIsMeaningful, false)

        let long = context(["paramecium": 4, "vorticella": 60], frames: 20).interpreted
        XCTAssertEqual(long.last?.band, .low)
        XCTAssertEqual(long.last?.lowIsMeaningful, true)
    }

    func testTalkExtensionReasons() {
        let must = context(["euglena": 10, "paramecium": 1])
        XCTAssertEqual(
            must.actions.first { $0.action.id == .talkExtension }?.because, "big changes suggested")

        let poor = context(["paramecium": 20, "amoeba": 20], level: .poor)
        XCTAssertEqual(poor.actions.first { $0.action.id == .talkExtension }?.because, "poor result")
    }

    func testFallbackPriorityHasEveryActionOnce() {
        XCTAssertEqual(AdviceActions.fallbackPriority.count, AdviceAction.ID.allCases.count)
        XCTAssertEqual(Set(AdviceActions.fallbackPriority), Set(AdviceAction.ID.allCases))
    }

    func testCurrentSampleFiguresMatchPastResults() {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 8, moisture: .flooded,
            countsByClass: ["Euglena": 3, "euglena": 2, "Paramecium": 5, "Stentor": 9], sweep: nil)
        let context = AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result), history: [])
        let past = PastResult(result, level: context.estimate.level)

        XCTAssertEqual(context.interpretedPerFrame, past.organismsPerFrame)
        XCTAssertEqual(context.interpretedKinds, past.interpretedKinds)
    }

    // MARK: Phase 4

    private func reason(_ context: AdviceContext, _ id: AdviceAction.ID) -> String? {
        context.actions.first { $0.action.id == id }?.reason
    }

    func testPoorEuglenaOnlySampleOffersWaterAndFertilizerNotStrawOrCompost() {
        let ids = actions(context(["euglena": 7], level: .poor, frames: 30))

        XCTAssertTrue(ids.contains(.refreshWater))
        XCTAssertTrue(ids.contains(.reviewFertilizer))
        XCTAssertFalse(ids.contains(.addCompost))
        XCTAssertFalse(ids.contains(.returnStraw))
    }

    func testStrawAndCompostAreExcludedWhenEuglenoidsAreDominantEvenIfNotHigh() {
        // Euglena at 0.5 per frame is typical, not high, but it is all there is.
        let context = context(["euglena": 5], frames: 10)

        XCTAssertTrue(context.patterns.contains(.euglenoidsDominant))
        XCTAssertFalse(context.interpreted.contains { $0.band == .high })
        XCTAssertFalse(actions(context).contains(.returnStraw))
        XCTAssertFalse(actions(context).contains(.addCompost))
    }

    func testLowDiversityIsFalseWhenNothingReadableWasCounted() {
        for counts in [[:], ["stentor": 6]] as [[String: Int]] {
            let ids = actions(context(counts))
            XCTAssertFalse(ids.contains(.returnStraw))
            XCTAssertFalse(ids.contains(.greenManure))
        }
    }

    func testEverySuggestedActionHasAReason() {
        let samples: [AdviceContext] = [
            context(["euglena": 10, "paramecium": 1]), context(["paramecium": 2], level: .poor),
            context(["pyrocystis": 10, "paramecium": 12]), context(nil, level: .notCounted),
            context(["nematode": 30, "paramecium": 20], level: .good),
        ]
        for context in samples {
            for suggested in context.actions {
                XCTAssertFalse(suggested.reason.isEmpty, "\(suggested.action.id)")
            }
        }
    }

    func testResampleFreshReasonNamesTheFirstTrigger() {
        let two = ["paramecium": 20, "amoeba": 20]
        XCTAssertEqual(reason(context([:], level: .tooFewToSay), .resampleFresh), AdviceReasons.tooFewToSay)
        XCTAssertEqual(reason(context(["stentor": 6]), .resampleFresh), AdviceReasons.nothingReadable)
        XCTAssertEqual(
            reason(context(["euglena": 30, "dinobryon": 1]), .resampleFresh), AdviceReasons.mixedSignals)
        XCTAssertEqual(reason(context(["paramecium": 30]), .resampleFresh), AdviceReasons.onlyOneKind)
        XCTAssertEqual(reason(context(two, stoppedEarly: true), .resampleFresh), AdviceReasons.stoppedEarly)
        XCTAssertEqual(reason(context(two, frames: 3), .resampleFresh), AdviceReasons.fewFrames)
    }

    func testStrawAndCoverCropReasonsNameLowAbundanceFirst() {
        let lowAbundance = context(["paramecium": 2], level: .poor, stage: .fallow)
        XCTAssertEqual(reason(lowAbundance, .returnStraw), AdviceReasons.strawLowAbundance)
        XCTAssertEqual(reason(lowAbundance, .greenManure), AdviceReasons.coverCropLowAbundance)

        let lowDiversity = context(["paramecium": 20, "amoeba": 20], stage: .fallow)
        XCTAssertEqual(reason(lowDiversity, .returnStraw), AdviceReasons.strawLowDiversity)
        XCTAssertEqual(reason(lowDiversity, .greenManure), AdviceReasons.coverCropLowDiversity)
    }

    func testFertilizerReasonMentionsRecentFertilizing() {
        let counts = ["euglena": 10, "paramecium": 1]
        XCTAssertEqual(reason(context(counts), .reviewFertilizer), AdviceReasons.fertilizer)
        XCTAssertEqual(
            reason(context(counts, recent: [.fertilized]), .reviewFertilizer),
            AdviceReasons.fertilizerAfterFertilizing)
    }

    func testExtensionReasonFollowsWhatTriggeredIt() {
        XCTAssertEqual(
            reason(context(["paramecium": 20, "amoeba": 20], level: .poor), .talkExtension),
            AdviceReasons.extensionAfterPoor)
        XCTAssertEqual(
            reason(context(["euglena": 10, "paramecium": 1]), .talkExtension),
            AdviceReasons.extensionBeforeBiggerChanges)
    }

    func testApprovedReasonsAreCleanAndShort() {
        for sentence in AdviceReasons.allSentences {
            let lowered = sentence.lowercased()
            for word in NeverSay.bannedWords {
                XCTAssertFalse(lowered.contains(word), sentence)
            }
            XCTAssertLessThanOrEqual(sentence.split(separator: " ").count, 20, sentence)
        }
    }
}
