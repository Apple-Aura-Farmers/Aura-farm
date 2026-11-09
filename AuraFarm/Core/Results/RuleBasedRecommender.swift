import Foundation

/// Fixed advice for each estimate level, so the recommendation card always has something to
/// say when the on-device model cannot run.
///
/// PLACEHOLDER copy: written for the prototype, not by an agronomist.
struct RuleBasedRecommender: RecommendationProviding {
    var availability: RecommenderAvailability { .available }

    func recommend(for result: SoilResult, estimate: SoilHealthEstimate) async throws -> Recommendation {
        Self.recommendation(for: estimate.level)
    }

    static func recommendation(for level: SoilHealthEstimate.Level) -> Recommendation {
        switch level {
        case .good:
            return Recommendation(
                summary: "Plenty of soil life was seen. Keep doing what is working.",
                actions: [
                    "Keep returning straw and crop leftovers to the field.",
                    "Keep the water schedule as it is.",
                ],
                source: .rules
            )
        case .fair:
            return Recommendation(
                summary: "Some soil life was seen. Small changes may help it grow.",
                actions: [
                    "Add compost or manure before the next planting.",
                    "Leave straw in the field instead of burning it.",
                    "Test again in a few weeks to see if it changes.",
                ],
                source: .rules
            )
        case .poor:
            return Recommendation(
                summary: "Little soil life was seen. It is worth checking before changing much.",
                actions: [
                    "Take a fresh sample from another part of the field.",
                    "Add organic matter such as compost or manure.",
                    "If the next test is low too, send a sample to a lab.",
                ],
                source: .rules
            )
        case .tooFewToSay:
            return Recommendation(
                summary: "Too little was seen to suggest anything about the soil.",
                actions: [
                    "Make a fresh slide, following the preparation guide.",
                    "Sweep it again, moving the slide slowly.",
                ],
                source: .rules
            )
        case .notCounted:
            return Recommendation(
                summary: "This sweep was not counted, so there is no advice yet.",
                actions: [
                    "Run the sweep again.",
                    "If counting keeps failing, restart the app.",
                ],
                source: .rules
            )
        }
    }
}
