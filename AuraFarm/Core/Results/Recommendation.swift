import Foundation

/// What to do about a result, in words a helper can read out to a farmer.
struct Recommendation: Equatable {
    enum Source: Equatable {
        /// Written on the phone by Apple's on-device model.
        case foundationModel
        /// Fixed advice for the estimate's level, used when the model cannot run.
        case rules
    }

    var summary: String
    /// Two to four short actions.
    var actions: [String]
    var source: Source
}

/// Where the recommendation card is.
enum RecommendationState: Equatable {
    case idle
    case generating
    case ready(Recommendation)
    /// The model ran and failed. The helper can try again.
    case failed(message: String)
}

/// Whether a recommender can run right now.
enum RecommenderAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

/// Writes a recommendation for a result. A protocol so the screen can be shown with a stub,
/// and so the on-device model can be swapped for something else later.
protocol RecommendationProviding {
    var availability: RecommenderAvailability { get }
    func recommend(for result: SoilResult, estimate: SoilHealthEstimate) async throws -> Recommendation
}
