import Foundation

/// What to do about a result, in words a helper can read out to a farmer.
struct Recommendation: Equatable, Codable {
    /// One thing to do.
    struct Step: Equatable, Codable {
        /// nil only for the "not counted" steps, which are not catalogue actions.
        var actionID: AdviceAction.ID?
        /// What the farmer is told to do: always the approved wording.
        var text: String
        /// The model's short reason. nil for standard advice.
        var why: String?
        var timing: String?

        enum CodingKeys: String, CodingKey {
            case actionID, text, why, timing
        }
    }

    enum Source: String, Equatable, Codable {
        /// Written on the phone by Apple's on-device model.
        case foundationModel
        /// Fixed advice for the estimate's level, used when the model cannot run.
        case rules
    }

    var summary: String
    /// What the model noticed in the sample. Empty for standard advice.
    var noticed: [String]
    /// Two or three.
    var steps: [Step]
    var source: Source
}

extension Recommendation.Step {
    /// An action id this version doesn't know, from a file a newer version wrote, becomes nil
    /// and the step keeps its text, so the file still opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try? container.decodeIfPresent(String.self, forKey: .actionID)
        actionID = rawID.flatMap { AdviceAction.ID(rawValue: $0) }
        text = try container.decode(String.self, forKey: .text)
        why = try container.decodeIfPresent(String.self, forKey: .why)
        timing = try container.decodeIfPresent(String.self, forKey: .timing)
    }
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

    /// `freshWording` asks for different wording from the last time; without it the same sample
    /// gets the same answer. `onProgress` is told where the writing has got to, and never
    /// carries any of the text.
    func recommend(
        for context: AdviceContext, freshWording: Bool,
        onProgress: @escaping @Sendable (AdviceProgress) -> Void
    ) async throws -> Recommendation

    /// Gets the writer ready, so the first answer is quicker.
    func prewarm()
}

extension RecommendationProviding {
    func recommend(for context: AdviceContext) async throws -> Recommendation {
        try await recommend(for: context, freshWording: false, onProgress: { _ in })
    }

    func prewarm() {}
}
