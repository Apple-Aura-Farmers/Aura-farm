import XCTest

@testable import AuraFarm

@MainActor
final class SoilResultViewModelTests: XCTestCase {
    /// A recommender that answers as told, and counts how often it was asked.
    private final class StubRecommender: RecommendationProviding {
        struct Failure: Error {}

        var availability: RecommenderAvailability = .available
        var fails = false
        /// Thrown instead of the generic failure, when set.
        var error: Error?
        /// Told to `onProgress` before answering, then waited on for `pauseAfterProgress`.
        var progressUpdates: [AdviceProgress] = []
        var pauseAfterProgress: Duration = .zero
        private(set) var calls = 0
        private(set) var freshRequests: [Bool] = []
        private(set) var prewarmCalls = 0

        func prewarm() { prewarmCalls += 1 }

        func recommend(
            for context: AdviceContext, freshWording: Bool,
            onProgress: @escaping @Sendable (AdviceProgress) -> Void
        ) async throws -> Recommendation {
            calls += 1
            freshRequests.append(freshWording)
            for update in progressUpdates { onProgress(update) }
            if pauseAfterProgress > .zero { try await Task.sleep(for: pauseAfterProgress) }
            if let error { throw error }
            if fails { throw Failure() }
            return Recommendation(
                summary: "From the model", noticed: ["Noticed"],
                steps: [
                    Recommendation.Step(actionID: .keepNotes, text: "One", why: "Why", timing: nil),
                    Recommendation.Step(actionID: .resampleLater, text: "Two", why: nil, timing: nil),
                ],
                source: .foundationModel)
        }
    }

    private func result(_ counts: [String: Int]?) -> SoilResult {
        SoilResult(
            sampleID: "A12",
            recordedAt: .now,
            framesKept: 12,
            moisture: .drained,
            countsByClass: counts,
            sweep: nil
        )
    }

    private let fairCounts = ["paramecium": 9, "euglena": 6, "vorticella": 3]

    nonisolated private static let pastResult = PastResult(
        recordedAt: .distantPast, moisture: .drained, cropStage: nil, organismsPerFrame: 1,
        interpretedKinds: 2,
        level: .fair)

    /// A fixed history, so no test reads the real sweeps.
    private func makeViewModel(
        _ counts: [String: Int]?, recommender: any RecommendationProviding,
        timeout: Duration = .seconds(30)
    ) -> SoilResultViewModel {
        SoilResultViewModel(
            result: result(counts), recommender: recommender, historyProvider: { _ in [Self.pastResult] },
            adviceTimeout: timeout, feedbackStore: InMemoryAdviceFeedbackStore())
    }

    /// A provider that only answers when it is cancelled.
    private struct NeverAnswers: RecommendationProviding {
        var availability: RecommenderAvailability { .available }

        func recommend(
            for context: AdviceContext, freshWording: Bool,
            onProgress: @escaping @Sendable (AdviceProgress) -> Void
        ) async throws -> Recommendation {
            try await Task.sleep(for: .seconds(3_600))
            throw CancellationError()
        }
    }

    func testAvailableModelWritesTheAdvice() async {
        let stub = StubRecommender()
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()

        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation.source, .foundationModel)
        XCTAssertNil(viewModel.modelUnavailableReason)
    }

    func testUnavailableModelFallsBackToStandardAdviceAndSaysWhy() async {
        let stub = StubRecommender()
        stub.availability = .unavailable(reason: "Off")
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()

        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation.source, .rules)
        XCTAssertEqual(viewModel.modelUnavailableReason, "Off")
        XCTAssertEqual(stub.calls, 0)
    }

    func testModelIsNotAskedAboutAnEmptySlide() async throws {
        let stub = StubRecommender()
        let viewModel = makeViewModel([:], recommender: stub)

        await viewModel.loadRecommendation()

        XCTAssertEqual(stub.calls, 0)
        let context = try XCTUnwrap(viewModel.adviceContext)
        XCTAssertEqual(
            viewModel.recommendationState, .ready(RuleBasedRecommender.recommendation(for: context)))
    }

    func testFailureCanBeRetried() async {
        let stub = StubRecommender()
        stub.fails = true
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()
        guard case .failed = viewModel.recommendationState else {
            return XCTFail("Expected a failure, got \(viewModel.recommendationState)")
        }

        stub.fails = false
        await viewModel.loadRecommendation()
        guard case .ready = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(stub.calls, 2)
    }

    func testBreakdownFollowsTheChosenTab() {
        let viewModel = makeViewModel(fairCounts, recommender: StubRecommender())

        XCTAssertEqual(viewModel.breakdownRows.count, 3)
        viewModel.selectedTaxonomy = .organismGroup
        XCTAssertEqual(viewModel.breakdownRows.map(\.count), [12, 6])
    }

    func testAdviceIsBuiltFromTheContextWithItsHistory() async {
        let viewModel = makeViewModel(fairCounts, recommender: StubRecommender())
        XCTAssertNil(viewModel.adviceContext)

        await viewModel.loadRecommendation()

        XCTAssertEqual(viewModel.adviceContext?.history, [Self.pastResult])
        XCTAssertEqual(viewModel.adviceContext?.estimate, viewModel.estimate)
        XCTAssertEqual(
            viewModel.adviceContext?.interpreted.map(\.note.label), ["paramecium", "euglena", "vorticella"])
    }

    func testFallbackPicksFromTheSampleContext() async throws {
        let stub = StubRecommender()
        stub.availability = .unavailable(reason: "Off")
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()

        let context = try XCTUnwrap(viewModel.adviceContext)
        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation, RuleBasedRecommender.recommendation(for: context))
        let offered = AdvicePromptBuilder.offeredActions(for: context).map(\.action.id)
        XCTAssertFalse(recommendation.steps.isEmpty)
        for step in recommendation.steps {
            XCTAssertTrue(offered.contains(try XCTUnwrap(step.actionID)))
        }
    }

    // MARK: Model errors

    func testUseStandardAdviceShowsTheRulesWithTheNote() async {
        let stub = StubRecommender()
        stub.error = AdviceFailure.useStandardAdvice(note: "Refused.")
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()

        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation.source, .rules)
        XCTAssertEqual(viewModel.modelUnavailableReason, "Refused.")
    }

    func testRetryShowsItsMessage() async {
        let stub = StubRecommender()
        stub.error = AdviceFailure.retry(message: "Busy.")
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()

        XCTAssertEqual(viewModel.recommendationState, .failed(message: "Busy."))
    }

    func testAnUnknownErrorShowsTheGenericMessage() async {
        let stub = StubRecommender()
        stub.fails = true
        let viewModel = makeViewModel(fairCounts, recommender: stub)

        await viewModel.loadRecommendation()

        guard case .failed(let message) = viewModel.recommendationState else {
            return XCTFail("Expected a failure, got \(viewModel.recommendationState)")
        }
        XCTAssertTrue(message.hasPrefix("The advice could not be written. Try again."))
    }

    func testAProviderThatNeverAnswersTimesOut() async {
        let viewModel = makeViewModel(fairCounts, recommender: NeverAnswers(), timeout: .milliseconds(50))

        await viewModel.loadRecommendation()

        XCTAssertEqual(
            viewModel.recommendationState,
            .failed(message: "Apple Intelligence is taking too long. Try again."))
    }

    func testCancellingDoesNotShowAnError() async throws {
        let viewModel = makeViewModel(fairCounts, recommender: NeverAnswers())
        let task = Task { await viewModel.loadRecommendation() }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value

        if case .failed = viewModel.recommendationState {
            XCTFail("A cancelled load must not show an error")
        }
    }

    // MARK: Saved advice

    private let savedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func sweepResult(_ counts: [String: Int]?) -> SoilResult {
        var result = result(counts)
        result.sweep = SavedSweep(
            url: URL(filePath: "/tmp/A12_f001", directoryHint: .isDirectory), manifest: nil,
            recordedAt: .now, byteCount: 0, frameURLs: [], panoramaURL: nil)
        return result
    }

    private func savingViewModel(
        _ recommender: any RecommendationProviding, store: InMemoryAdviceStore, counts: [String: Int]? = nil,
        withSweep: Bool = true, timeout: Duration = .seconds(30),
        feedbackStore: InMemoryAdviceFeedbackStore = InMemoryAdviceFeedbackStore()
    ) -> SoilResultViewModel {
        let counts = counts ?? fairCounts
        return SoilResultViewModel(
            result: withSweep ? sweepResult(counts) : result(counts), recommender: recommender,
            historyProvider: { _ in [] }, adviceTimeout: timeout, adviceStore: store,
            clock: { [savedDate] in savedDate }, feedbackStore: feedbackStore)
    }

    private func savedAdvice(version: String = AdviceContentVersion.current) -> SavedAdvice {
        SavedAdvice(
            recommendation: Recommendation(
                summary: "Saved", noticed: [],
                steps: [Recommendation.Step(actionID: .keepNotes, text: "Kept", why: "Why", timing: nil)],
                source: .foundationModel),
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000), contentVersion: version, appVersion: "1.0")
    }

    func testSavedAdviceIsShownWithoutCallingTheProvider() async throws {
        let stub = StubRecommender()
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(stub, store: store)
        try store.save(savedAdvice(), for: try XCTUnwrap(viewModel.result.sweep))

        await viewModel.loadRecommendation()

        XCTAssertEqual(viewModel.recommendationState, .ready(savedAdvice().recommendation))
        XCTAssertEqual(stub.calls, 0)
        XCTAssertEqual(viewModel.savedAt, savedAdvice().writtenAt)
        XCTAssertFalse(viewModel.savedFromOlderRules)
        XCTAssertNil(viewModel.modelUnavailableReason)
        XCTAssertNotNil(viewModel.adviceContext)
    }

    func testSavedAdviceFromOlderRulesSaysSo() async throws {
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(StubRecommender(), store: store)
        try store.save(savedAdvice(version: "2026-01-01-old"), for: try XCTUnwrap(viewModel.result.sweep))

        await viewModel.loadRecommendation()

        XCTAssertTrue(viewModel.savedFromOlderRules)
    }

    func testModelAdviceIsSavedAfterSuccess() async throws {
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(StubRecommender(), store: store)

        await viewModel.loadRecommendation()

        let saved = try XCTUnwrap(store.load(for: try XCTUnwrap(viewModel.result.sweep)))
        XCTAssertEqual(saved.recommendation.summary, "From the model")
        XCTAssertEqual(saved.recommendation.source, .foundationModel)
        XCTAssertEqual(saved.writtenAt, savedDate)
        XCTAssertEqual(saved.contentVersion, AdviceContentVersion.current)
        XCTAssertEqual(viewModel.savedAt, savedDate)
        XCTAssertFalse(viewModel.savedFromOlderRules)
    }

    func testAFailedSaveLeavesTheScreenAsItIs() async {
        let store = InMemoryAdviceStore()
        store.failsToSave = true
        let viewModel = savingViewModel(StubRecommender(), store: store)

        await viewModel.loadRecommendation()

        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation.summary, "From the model")
        XCTAssertNil(viewModel.savedAt)
    }

    func testStandardAdviceIsNotSaved() async throws {
        let stub = StubRecommender()
        stub.availability = .unavailable(reason: "Off")
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(stub, store: store)

        await viewModel.loadRecommendation()
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertNil(store.load(for: try XCTUnwrap(viewModel.result.sweep)))

        // Advice that failed the checks falls back to standard advice, which isn't saved either.
        let refusing = StubRecommender()
        refusing.error = AdviceFailure.useStandardAdvice(note: "Refused.")
        let second = savingViewModel(refusing, store: store)
        await second.loadRecommendation()
        XCTAssertEqual(store.saveCount, 0)
    }

    func testNothingIsSavedWithoutASweep() async {
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(StubRecommender(), store: store, withSweep: false)

        await viewModel.loadRecommendation()

        XCTAssertEqual(store.saveCount, 0)
        XCTAssertNil(viewModel.savedAt)
    }

    func testWriteAgainAsksForFreshWordingAndOverwritesTheSave() async throws {
        let stub = StubRecommender()
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(stub, store: store)
        let sweep = try XCTUnwrap(viewModel.result.sweep)
        try store.save(savedAdvice(version: "2026-01-01-old"), for: sweep)

        await viewModel.writeAgain()

        XCTAssertEqual(stub.freshRequests, [true])
        XCTAssertEqual(try XCTUnwrap(store.load(for: sweep)).recommendation.summary, "From the model")
        XCTAssertEqual(viewModel.savedAt, savedDate)
        XCTAssertFalse(viewModel.savedFromOlderRules)
    }

    private static let keptNote = "New advice couldn't be written, so the saved advice is shown."

    func testAFailedWriteAgainKeepsTheSavedAdviceOnScreenForEveryKindOfFailure() async throws {
        let failures: [(String, (StubRecommender) -> Void, Duration)] = [
            ("retry", { $0.error = AdviceFailure.retry(message: "Busy.") }, .seconds(30)),
            (
                "standard advice",
                { $0.error = AdviceFailure.useStandardAdvice(note: "Refused.") }, .seconds(30)
            ),
            ("unknown error", { $0.fails = true }, .seconds(30)),
            ("timeout", { $0.pauseAfterProgress = .seconds(3_600) }, .milliseconds(50)),
        ]
        for (name, configure, timeout) in failures {
            let stub = StubRecommender()
            configure(stub)
            let store = InMemoryAdviceStore()
            let viewModel = savingViewModel(stub, store: store, timeout: timeout)
            let sweep = try XCTUnwrap(viewModel.result.sweep)
            try store.save(savedAdvice(version: "2026-01-01-old"), for: sweep)
            let savesBefore = store.saveCount

            await viewModel.writeAgain()

            XCTAssertEqual(viewModel.recommendationState, .ready(savedAdvice().recommendation), name)
            XCTAssertEqual(viewModel.savedAt, savedAdvice().writtenAt, name)
            XCTAssertTrue(viewModel.savedFromOlderRules, name)
            XCTAssertTrue(viewModel.modelUnavailableReason?.hasPrefix(Self.keptNote) ?? false, name)
            XCTAssertEqual(store.load(for: sweep), savedAdvice(version: "2026-01-01-old"), name)
            XCTAssertEqual(store.saveCount, savesBefore, name)
        }
    }

    func testWithoutSavedAdviceAFailedWriteAgainShowsTheFailureAsBefore() async {
        let stub = StubRecommender()
        stub.error = AdviceFailure.retry(message: "Busy.")
        let viewModel = savingViewModel(stub, store: InMemoryAdviceStore())

        await viewModel.writeAgain()

        XCTAssertEqual(viewModel.recommendationState, .failed(message: "Busy."))
        XCTAssertNil(viewModel.modelUnavailableReason)
    }

    func testTryAgainAfterAFailedWriteAgainStaysFresh() async throws {
        let stub = StubRecommender()
        stub.error = AdviceFailure.retry(message: "Busy.")
        let store = InMemoryAdviceStore()
        let viewModel = savingViewModel(stub, store: store)
        let sweep = try XCTUnwrap(viewModel.result.sweep)
        try store.save(savedAdvice(), for: sweep)

        await viewModel.writeAgain()
        stub.error = nil
        // As the screen does: with the last requested mode.
        await viewModel.loadRecommendation(freshWording: viewModel.wantsFreshWording)

        XCTAssertEqual(stub.freshRequests, [true, true])
        XCTAssertEqual(try XCTUnwrap(store.load(for: sweep)).recommendation.summary, "From the model")
        XCTAssertNil(viewModel.modelUnavailableReason)
    }

    // MARK: Feedback

    func testRatingWithASweepIsWrittenWithTheSample() async throws {
        let feedbackStore = InMemoryAdviceFeedbackStore()
        let viewModel = savingViewModel(
            StubRecommender(), store: InMemoryAdviceStore(), feedbackStore: feedbackStore)
        await viewModel.loadRecommendation()

        await viewModel.rate(.notUseful, reasons: [.doesNotFit])

        let sweep = try XCTUnwrap(viewModel.result.sweep)
        let saved = try XCTUnwrap(feedbackStore.all(for: sweep).first)
        XCTAssertEqual(saved.rating, .notUseful)
        XCTAssertEqual(saved.reasons, [.doesNotFit])
        XCTAssertEqual(saved.source, .foundationModel)
        XCTAssertEqual(saved.recommendation.summary, "From the model")
        XCTAssertEqual(saved.contentVersion, AdviceContentVersion.current)
        XCTAssertEqual(saved.givenAt, savedDate)
        XCTAssertEqual(viewModel.feedback, saved)
    }

    func testRatingWithoutASweepIsKeptInMemoryOnly() async {
        let feedbackStore = InMemoryAdviceFeedbackStore()
        let viewModel = savingViewModel(
            StubRecommender(), store: InMemoryAdviceStore(), withSweep: false, feedbackStore: feedbackStore)
        await viewModel.loadRecommendation()

        await viewModel.rate(.useful)

        XCTAssertEqual(viewModel.feedback?.rating, .useful)
    }

    func testAFailedWriteKeepsTheRatingInMemory() async throws {
        let feedbackStore = InMemoryAdviceFeedbackStore()
        feedbackStore.failsToRecord = true
        let viewModel = savingViewModel(
            StubRecommender(), store: InMemoryAdviceStore(), feedbackStore: feedbackStore)
        await viewModel.loadRecommendation()

        await viewModel.rate(.useful)

        XCTAssertEqual(viewModel.feedback?.rating, .useful)
        XCTAssertEqual(feedbackStore.all(for: try XCTUnwrap(viewModel.result.sweep)), [])
    }

    func testChangingTheRatingKeepsTheSameEntry() async throws {
        let feedbackStore = InMemoryAdviceFeedbackStore()
        let viewModel = savingViewModel(
            StubRecommender(), store: InMemoryAdviceStore(), feedbackStore: feedbackStore)
        await viewModel.loadRecommendation()

        await viewModel.rate(.useful)
        let id = viewModel.feedback?.id
        await viewModel.rate(.notUseful, reasons: [.seemsWrong])

        XCTAssertEqual(viewModel.feedback?.id, id)
        let entries = feedbackStore.all(for: try XCTUnwrap(viewModel.result.sweep))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.rating, .notUseful)
        XCTAssertEqual(entries.first?.reasons, [.seemsWrong])
    }

    func testFeedbackClearsWhenANewRecommendationIsShown() async {
        let viewModel = savingViewModel(StubRecommender(), store: InMemoryAdviceStore())
        await viewModel.loadRecommendation()
        await viewModel.rate(.useful)
        XCTAssertNotNil(viewModel.feedback)

        await viewModel.writeAgain()

        XCTAssertNil(viewModel.feedback)
    }

    func testRatingsOnSavedAdviceComeBackWhenItIsShownAgain() async throws {
        let store = InMemoryAdviceStore()
        let feedbackStore = InMemoryAdviceFeedbackStore()
        let first = savingViewModel(StubRecommender(), store: store, feedbackStore: feedbackStore)
        await first.loadRecommendation()
        await first.rate(.useful)

        let reopened = savingViewModel(StubRecommender(), store: store, feedbackStore: feedbackStore)
        await reopened.loadRecommendation()

        XCTAssertEqual(reopened.feedback?.rating, .useful)
    }

    func testProgressUpdatesArriveAndClearAtTheEnd() async throws {
        let stub = StubRecommender()
        stub.progressUpdates = [.noticing, .choosingSteps(chosen: 1)]
        stub.pauseAfterProgress = .milliseconds(300)
        let viewModel = makeViewModel(fairCounts, recommender: stub)
        let task = Task { await viewModel.loadRecommendation() }

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(viewModel.progress, .choosingSteps(chosen: 1))

        await task.value
        XCTAssertNil(viewModel.progress)
        guard case .ready = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
    }

    func testTheModelIsPrewarmedOnceWhenAvailableAndNeverWhenNot() async {
        let available = StubRecommender()
        await makeViewModel(fairCounts, recommender: available).loadRecommendation()
        XCTAssertEqual(available.prewarmCalls, 1)

        let unavailable = StubRecommender()
        unavailable.availability = .unavailable(reason: "Off")
        await makeViewModel(fairCounts, recommender: unavailable).loadRecommendation()
        XCTAssertEqual(unavailable.prewarmCalls, 0)

        let notNeeded = StubRecommender()
        await makeViewModel([:], recommender: notNeeded).loadRecommendation()
        XCTAssertEqual(notNeeded.prewarmCalls, 0)
    }

    func testCanWriteAgainOnlyForModelAdviceWithTheModelAvailable() async {
        let stub = StubRecommender()
        let viewModel = makeViewModel(fairCounts, recommender: stub)
        XCTAssertFalse(viewModel.canWriteAgain)

        await viewModel.loadRecommendation()
        XCTAssertTrue(viewModel.canWriteAgain)

        stub.availability = .unavailable(reason: "Off")
        XCTAssertFalse(viewModel.canWriteAgain)

        let standard = StubRecommender()
        standard.availability = .unavailable(reason: "Off")
        let fallbackModel = makeViewModel(fairCounts, recommender: standard)
        await fallbackModel.loadRecommendation()
        XCTAssertFalse(fallbackModel.canWriteAgain)
    }
}
