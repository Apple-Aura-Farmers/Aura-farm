import Foundation
import Observation

/// Holds what the results screen shows and fetches the recommendation. The estimate is
/// worked out once; the recommendation is written when the screen opens.
@MainActor
@Observable
final class SoilResultViewModel {
    let result: SoilResult
    let estimate: SoilHealthEstimate

    private(set) var recommendationState: RecommendationState = .idle
    /// Why the on-device model was not used, when the advice shown is the fixed one instead.
    private(set) var modelUnavailableReason: String?

    var selectedTaxonomy: OrganismTaxonomy = .modelClass
    var isBreakdownExpanded = false

    @ObservationIgnored private let recommender: any RecommendationProviding
    @ObservationIgnored private let fallback: any RecommendationProviding
    @ObservationIgnored private let mapping: ProvisionalTaxonMapping

    init(
        result: SoilResult,
        estimator: any SoilHealthEstimating = PlaceholderSoilHealthEstimator(),
        recommender: any RecommendationProviding = FoundationModelRecommender(),
        fallback: any RecommendationProviding = RuleBasedRecommender(),
        mapping: ProvisionalTaxonMapping = ProvisionalTaxonMapping()
    ) {
        self.result = result
        self.estimate = estimator.estimate(result)
        self.recommender = recommender
        self.fallback = fallback
        self.mapping = mapping
    }

    /// The breakdown rows for the chosen tab. Empty when nothing was counted.
    var breakdownRows: [TaxonCount] {
        selectedTaxonomy.rows(from: result.countsByClass ?? [:], mapping: mapping)
    }

    /// Asks the model for advice, or uses the fixed advice when the model cannot run or there
    /// is too little to go on: a model asked about an empty slide only makes something up.
    func loadRecommendation() async {
        recommendationState = .generating
        modelUnavailableReason = nil

        let needsModel = [SoilHealthEstimate.Level.good, .fair, .poor].contains(estimate.level)
        var provider = fallback
        if needsModel {
            switch recommender.availability {
            case .available:
                provider = recommender
            case .unavailable(let reason):
                modelUnavailableReason = reason
            }
        }

        do {
            let recommendation = try await provider.recommend(for: result, estimate: estimate)
            guard !Task.isCancelled else { return }
            recommendationState = .ready(recommendation)
        } catch {
            guard !Task.isCancelled else { return }
            recommendationState = .failed(message: "The advice could not be written. Try again.")
        }
    }
}
