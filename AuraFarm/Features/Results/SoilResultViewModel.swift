import Foundation
import Observation
import os

/// Holds what the results screen shows and fetches the recommendation. The estimate is
/// worked out once; the recommendation is written when the screen opens.
@MainActor
@Observable
final class SoilResultViewModel {
    let result: SoilResult
    let estimate: SoilHealthEstimate

    private(set) var recommendationState: RecommendationState = .idle
    /// Why standard advice is shown instead of the model's, when it is.
    private(set) var modelUnavailableReason: String?
    /// What the advice was built from, kept so debug tools can show it.
    private(set) var adviceContext: AdviceContext?
    /// Where the model has got to while it writes. nil when it isn't writing.
    private(set) var progress: AdviceProgress?
    /// When the advice on screen was saved with the sample, if it was.
    private(set) var savedAt: Date?
    /// True when the saved advice on screen was written with older advice rules.
    private(set) var savedFromOlderRules = false
    /// The helper's rating of the advice on screen, if they gave one.
    private(set) var feedback: AdviceFeedback?
    /// The last requested mode, so Try again after Write again asks for fresh wording too.
    private(set) var wantsFreshWording = false

    var selectedTaxonomy: OrganismTaxonomy = .modelClass
    var isBreakdownExpanded = false

    @ObservationIgnored private let recommender: any RecommendationProviding
    @ObservationIgnored private let fallback: any RecommendationProviding
    @ObservationIgnored private let mapping: ProvisionalTaxonMapping
    @ObservationIgnored private let historyProvider: @Sendable (SoilResult) async -> [PastResult]
    @ObservationIgnored private let contextBuilder: AdviceContextBuilder
    /// PLACEHOLDER: how long the provider has to answer. Not measured on a device.
    @ObservationIgnored private let adviceTimeout: Duration
    @ObservationIgnored private let adviceStore: (any AdviceStore)?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let feedbackStore: (any AdviceFeedbackStore)?

    init(
        result: SoilResult,
        estimator: any SoilHealthEstimating = PlaceholderSoilHealthEstimator(),
        recommender: any RecommendationProviding = FoundationModelRecommender(),
        fallback: any RecommendationProviding = RuleBasedRecommender(),
        mapping: ProvisionalTaxonMapping = ProvisionalTaxonMapping(),
        historyProvider: @escaping @Sendable (SoilResult) async -> [PastResult] = SoilResultViewModel
            .savedHistory,
        contextBuilder: AdviceContextBuilder = AdviceContextBuilder(),
        adviceTimeout: Duration = .seconds(30),
        adviceStore: (any AdviceStore)? = FileAdviceStore(),
        clock: @escaping @Sendable () -> Date = { Date() },
        feedbackStore: (any AdviceFeedbackStore)? = FileAdviceFeedbackStore()
    ) {
        self.result = result
        self.estimate = estimator.estimate(result)
        self.recommender = recommender
        self.fallback = fallback
        self.mapping = mapping
        self.historyProvider = historyProvider
        self.contextBuilder = contextBuilder
        self.adviceTimeout = adviceTimeout
        self.adviceStore = adviceStore
        self.clock = clock
        self.feedbackStore = feedbackStore
    }

    /// Earlier samples of the same plot among the saved sweeps. Off the main actor, because
    /// listing the sweeps reads every manifest from disk.
    nonisolated static let savedHistory: @Sendable (SoilResult) async -> [PastResult] = { result in
        await Task.detached(priority: .userInitiated) {
            PlotHistory.earlierResults(for: result, among: SweepLibrary.manifestsOnly())
        }.value
    }

    /// The "Based on" line for the advice, once the context is built.
    var adviceBasis: String? {
        adviceContext.flatMap { AdviceBasis.line(for: $0) }
    }

    /// True when the advice on screen came from the model and the model can write it again.
    var canWriteAgain: Bool {
        guard case .ready(let recommendation) = recommendationState, recommendation.source == .foundationModel
        else { return false }
        return recommender.availability == .available
    }

    /// The breakdown rows for the chosen tab. Empty when nothing was counted.
    var breakdownRows: [TaxonCount] {
        selectedTaxonomy.rows(from: result.countsByClass ?? [:], mapping: mapping)
    }

    /// Remembers that the next load should ask for fresh wording, for a Write again button that
    /// restarts the screen's task.
    func requestFreshWording() {
        wantsFreshWording = true
    }

    /// Asks the model for new wording. On success it replaces the saved advice. On failure the
    /// saved advice stays on disk and on screen, with a note; without saved advice the screen
    /// shows the failure with Try again.
    func writeAgain() async {
        await loadRecommendation(freshWording: true)
    }

    /// Shows saved advice when there is some, and otherwise asks the model for advice, or uses
    /// the fixed advice when the model cannot run or there is too little to go on: a model asked
    /// about an empty slide only makes something up.
    ///
    /// `freshWording` skips the saved advice and asks for different wording.
    ///
    /// In DEBUG builds a failure message also carries the underlying error, so a failure on a
    /// phone shows the actual FoundationModels error.
    func loadRecommendation(freshWording: Bool = false) async {
        wantsFreshWording = freshWording
        recommendationState = .generating
        modelUnavailableReason = nil
        progress = nil
        savedAt = nil
        savedFromOlderRules = false
        feedback = nil

        let needsModel = [SoilHealthEstimate.Level.good, .fair, .poor].contains(estimate.level)

        if !freshWording, needsModel, let saved = await savedAdvice() {
            guard !Task.isCancelled else { return }
            savedAt = saved.writtenAt
            savedFromOlderRules = saved.isFromOlderRules
            recommendationState = .ready(saved.recommendation)
            feedback = await matchingFeedback(for: saved.recommendation)
            adviceContext = await buildContext()
            return
        }

        var provider = fallback
        if needsModel {
            switch recommender.availability {
            case .available:
                provider = recommender
                recommender.prewarm()
            case .unavailable(let reason):
                modelUnavailableReason = reason
            }
        }

        guard !Task.isCancelled else { return }
        let context = await buildContext()
        guard !Task.isCancelled else { return }
        adviceContext = context

        do {
            let recommendation = try await recommendation(
                from: provider, context: context, freshWording: freshWording)
            guard !Task.isCancelled else { return }
            progress = nil
            recommendationState = .ready(recommendation)
            await saveIfModelAdvice(recommendation)
        } catch {
            guard !Task.isCancelled else { return }
            progress = nil
            if freshWording, await showSavedAdviceAfterFailure(error) { return }
            switch error as? AdviceFailure {
            case .useStandardAdvice(let note)?:
                await showStandardAdvice(note: note, context: context)
            case .retry(let message)?:
                recommendationState = .failed(message: message)
            case nil:
                recommendationState = .failed(message: Self.genericMessage(for: error))
            }
        }
    }

    /// After a failed Write again the saved advice stays on screen, with a note. The file is not
    /// touched. False when this sample has no saved advice.
    private func showSavedAdviceAfterFailure(_ error: Error) async -> Bool {
        guard let saved = await savedAdvice() else { return false }
        guard !Task.isCancelled else { return true }
        savedAt = saved.writtenAt
        savedFromOlderRules = saved.isFromOlderRules
        var note = "New advice couldn't be written, so the saved advice is shown."
        #if DEBUG
            let detail: String
            switch error as? AdviceFailure {
            case .useStandardAdvice(let text)?: detail = text
            case .retry(let text)?: detail = text
            case nil: detail = String(describing: error)
            }
            note += "\n(Debug: \(detail))"
        #endif
        modelUnavailableReason = note
        recommendationState = .ready(saved.recommendation)
        feedback = await matchingFeedback(for: saved.recommendation)
        return true
    }

    /// Rates the advice on screen. The same entry is updated while the same advice is shown, so
    /// changing a rating doesn't add another. It is written with the sample when there is a
    /// sweep; otherwise, or if the write fails, it is kept in memory only.
    func rate(_ rating: AdviceFeedback.Rating, reasons: [AdviceFeedback.Reason] = []) async {
        guard case .ready(let recommendation) = recommendationState else { return }
        let entry = AdviceFeedback(
            id: feedback?.id ?? UUID(), givenAt: clock(), rating: rating, reasons: reasons,
            source: recommendation.source, recommendation: recommendation,
            contentVersion: AdviceContentVersion.current,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        feedback = entry
        guard let sweep = result.sweep, let store = feedbackStore else { return }
        await Task.detached(priority: .utility) {
            do {
                try store.record(entry, for: sweep)
            } catch {
                #if DEBUG
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")
                        .debug("Feedback could not be saved: \(String(describing: error), privacy: .public)")
                #endif
            }
        }.value
    }

    /// Feedback already given on this exact advice, for saved advice shown again.
    private func matchingFeedback(for recommendation: Recommendation) async -> AdviceFeedback? {
        guard let sweep = result.sweep, let store = feedbackStore else { return nil }
        return await Task.detached(priority: .userInitiated) {
            store.all(for: sweep).last { $0.recommendation == recommendation }
        }.value
    }

    private func buildContext() async -> AdviceContext {
        let history = await historyProvider(result)
        return contextBuilder.context(for: result, estimate: estimate, history: history)
    }

    /// The advice saved with this sample, read off the main actor.
    private func savedAdvice() async -> SavedAdvice? {
        guard let sweep = result.sweep, let store = adviceStore else { return nil }
        return await Task.detached(priority: .userInitiated) { store.load(for: sweep) }.value
    }

    /// Keeps the model's advice with the sample. Standard advice is never saved, so Apple
    /// Intelligence gets another chance the next time the sample is opened. A failed save leaves
    /// the screen as it is.
    private func saveIfModelAdvice(_ recommendation: Recommendation) async {
        guard recommendation.source == .foundationModel, let sweep = result.sweep, let store = adviceStore
        else { return }
        let advice = SavedAdvice(
            recommendation: recommendation,
            writtenAt: clock(),
            contentVersion: AdviceContentVersion.current,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let saved = await Task.detached(priority: .utility) {
            do {
                try store.save(advice, for: sweep)
                return true
            } catch {
                #if DEBUG
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")
                        .debug("Advice could not be saved: \(String(describing: error), privacy: .public)")
                #endif
                return false
            }
        }.value
        guard !Task.isCancelled else { return }
        savedAt = saved ? advice.writtenAt : nil
        savedFromOlderRules = false
    }

    /// The fixed advice, with the reason the model's was not used.
    private func showStandardAdvice(note: String, context: AdviceContext) async {
        do {
            let standard = try await fallback.recommend(for: context)
            guard !Task.isCancelled else { return }
            modelUnavailableReason = note
            recommendationState = .ready(standard)
        } catch {
            guard !Task.isCancelled else { return }
            recommendationState = .failed(message: Self.genericMessage(for: error))
        }
    }

    /// Races the provider against the timeout, and cancels whichever is still running.
    private func recommendation(
        from provider: any RecommendationProviding, context: AdviceContext, freshWording: Bool
    ) async throws -> Recommendation {
        let timeout = adviceTimeout
        let onProgress: @Sendable (AdviceProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                // Late news, after the answer or a failure, is ignored.
                guard let self, self.recommendationState == .generating else { return }
                self.progress = progress
            }
        }
        return try await withThrowingTaskGroup(of: Recommendation.self) { group in
            group.addTask {
                try await provider.recommend(for: context, freshWording: freshWording, onProgress: onProgress)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AdviceFailure.retry(message: AdviceFailure.timeoutMessage)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private static func genericMessage(for error: Error) -> String {
        var message = AdviceFailure.genericMessage
        #if DEBUG
            message += "\n(Debug: \(String(describing: error)))"
        #endif
        return message
    }
}
