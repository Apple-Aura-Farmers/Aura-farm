import Foundation

/// Standard advice for when the on-device model cannot run. It picks from the same approved
/// actions the model is offered, in `AdviceActions.fallbackPriority` order.
///
/// PLACEHOLDER copy: the summaries were written for the prototype, not by an agronomist.
struct RuleBasedRecommender: RecommendationProviding {
    var availability: RecommenderAvailability { .available }

    func recommend(
        for context: AdviceContext, freshWording: Bool,
        onProgress: @escaping @Sendable (AdviceProgress) -> Void
    ) async throws -> Recommendation {
        Self.recommendation(for: context)
    }

    static func recommendation(for context: AdviceContext) -> Recommendation {
        Recommendation(
            summary: summary(for: context), noticed: [], steps: steps(for: context), source: .rules)
    }

    /// At most three offered actions, most important first, each with its approved reason. An
    /// action marked must-check always comes with "talk to your extension officer". A sweep
    /// that was never counted gets fixed steps instead, because no catalogue action fits it.
    static func steps(for context: AdviceContext) -> [Recommendation.Step] {
        guard context.estimate.level != .notCounted else {
            return [
                Recommendation.Step(
                    actionID: nil, text: "Run the sweep again.", why: AdviceReasons.notCounted, timing: nil),
                Recommendation.Step(
                    actionID: nil, text: "If counting keeps failing, restart the app.",
                    why: AdviceReasons.notCounted, timing: nil),
            ]
        }
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        let picked = AdviceActions.fallbackPriority
            .compactMap { id in offered.first { $0.action.id == id } }
            .prefix(AdviceResponseMapper.maxSteps)
            .map { AdviceStepRules.step(for: $0, why: nil) }
        return AdviceStepRules.ensuringExtensionStep(Array(picked), offered: offered)
    }

    static func summary(for context: AdviceContext) -> String {
        if context.patterns.contains(where: \.blocksImprovementActions) {
            return "This sample is hard to read. Check it again before changing anything."
        }
        if context.patterns.contains(where: \.isConcern) {
            return "Some of what was seen is worth a closer look."
        }
        switch context.estimate.level {
        case .good: return "Plenty of soil life was seen. Keep doing what is working."
        case .fair: return "Some soil life was seen. Small changes may help it grow."
        case .poor: return "Little soil life was seen. It is worth checking before changing much."
        case .tooFewToSay: return "Too little was seen to suggest anything about the soil."
        case .notCounted: return "This sweep was not counted, so there is no advice yet."
        }
    }
}
