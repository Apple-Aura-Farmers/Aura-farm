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
        if context.result.isSoilOnly {
            // No test was taken, so only what the soil measurements call for is offered.
            let soil = context.actions.filter(\.fromSoil)
                .sorted { rank($0.action.id) < rank($1.action.id) }
            let picked = soil.prefix(AdviceComposer.maxSoilSteps).map { suggested -> Recommendation.Step in
                var step = AdviceStepRules.step(for: suggested, why: nil)
                step.group = .soil
                return step
            }
            return AdviceStepRules.ensuringExtensionStep(Array(picked), offered: context.actions)
        }
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

    private static func rank(_ id: AdviceAction.ID) -> Int {
        AdviceActions.fallbackPriority.firstIndex(of: id) ?? Int.max
    }

    static func summary(for context: AdviceContext) -> String {
        if context.result.isSoilOnly {
            return context.actions.contains(where: \.fromSoil)
                ? String(
                    localized:
                        "This is from the soil measurements only. No microscope test has been taken yet.")
                : AdviceComposer.soilAllGood
        }
        let base = labSummary(for: context)
        // One more sentence when the soil measurements call for steps of their own, so the summary
        // does not read as if only the microscope was looked at.
        guard context.actions.contains(where: \.fromSoil) else { return base }
        return base + " " + String(localized: "The soil measurements point to a few changes too.")
    }

    private static func labSummary(for context: AdviceContext) -> String {
        if context.patterns.contains(where: \.blocksImprovementActions) {
            return String(localized: "This sample is hard to read. Check it again before changing anything.")
        }
        if context.patterns.contains(where: \.isConcern) {
            return String(localized: "Some of what was seen is worth a closer look.")
        }
        switch context.estimate.level {
        case .good: return String(localized: "Plenty of soil life was seen. Keep doing what is working.")
        case .fair: return String(localized: "Some soil life was seen. Small changes may help it grow.")
        case .poor:
            return String(localized: "Little soil life was seen. It is worth checking before changing much.")
        case .tooFewToSay: return String(localized: "Too little was seen to suggest anything about the soil.")
        case .notCounted: return String(localized: "This sweep was not counted, so there is no advice yet.")
        }
    }
}
