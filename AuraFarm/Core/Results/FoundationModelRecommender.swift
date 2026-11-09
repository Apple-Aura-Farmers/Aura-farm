import Foundation
import FoundationModels

/// Writes a recommendation with Apple's on-device language model.
///
/// The model knows nothing about this soil beyond what the prompt tells it, and nothing it
/// says has been checked by an agronomist. The instructions keep it cautious and plain, and
/// the screen labels what it writes as generated.
struct FoundationModelRecommender: RecommendationProviding {
    var model: SystemLanguageModel = .default

    var availability: RecommenderAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This iPhone cannot run Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is turned off in Settings.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Apple Intelligence is still downloading. Try again later.")
        case .unavailable:
            return .unavailable(reason: "Apple Intelligence is not available right now.")
        }
    }

    func recommend(for result: SoilResult, estimate: SoilHealthEstimate) async throws -> Recommendation {
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(for: result, estimate: estimate),
            generating: GeneratedRecommendation.self
        )
        return Recommendation(
            summary: response.content.summary,
            actions: response.content.actions,
            source: .foundationModel
        )
    }

    static let instructions = """
        You help a field helper who visits rice farmers. The helper has looked at a drop of \
        paddy soil under a microscope, and an app counted the microorganisms it saw. You \
        suggest what the farmer could do next.

        Rules:
        - Write short, plain sentences a helper can read out loud to a farmer.
        - Suggest practical, low-cost actions for a rice paddy, such as organic matter, \
        water management, or how often to till.
        - Never claim the soil is healthy or unhealthy for certain. These counts are rough \
        and not checked against a lab.
        - Do not name chemicals, brands or doses.
        - If the counts are low, say a fresh sample may be needed before changing anything.
        """

    /// What the model is told about this sample.
    static func prompt(for result: SoilResult, estimate: SoilHealthEstimate) -> String {
        let counts =
            result.countsByClass.map { counts in
                counts.isEmpty
                    ? "none"
                    : counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
                        .joined(separator: ", ")
            } ?? "not counted"
        return """
            Soil moisture when sampled: \(result.moisture.rawValue).
            Frames looked at: \(result.framesKept).
            Organisms counted by kind: \(counts).
            Rough estimate: \(estimate.level.rawValue), confidence \(estimate.confidence.rawValue).
            Why: \(estimate.reasons.joined(separator: " "))
            Suggest what the farmer could do next.
            """
    }
}

/// The shape the model fills in.
@Generable
struct GeneratedRecommendation {
    @Guide(description: "One or two plain sentences on what the counts suggest, with no certainty.")
    var summary: String

    @Guide(description: "Short practical actions for the farmer, each one sentence.", .count(2...4))
    var actions: [String]
}
