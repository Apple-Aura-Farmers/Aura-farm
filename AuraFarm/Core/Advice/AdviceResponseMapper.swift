import Foundation
import os

/// Turns the model's answer into a recommendation. The model only picks actions and gives
/// reasons; the wording on screen is always the approved wording, a reason that is missing or
/// fails a check is replaced by the approved one, and picks the prompt did not offer are
/// dropped.
///
/// The rules mirror `docs/advice-content.md` (the team's "Advice content", approved
/// 9 November 2026). Change them in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum AdviceResponseMapper {
    struct Outcome: Equatable {
        var recommendation: Recommendation
        /// Picks thrown away: not offered, unknown, repeated, past the third, or replaced by
        /// the extension-officer step.
        var droppedPicks: Int
        /// The parts of the model's own words that failed a check.
        var findings: [AdviceOutputChecker.Finding]
        /// True when more parts failed than the limits allow, so standard advice should be
        /// shown instead of this recommendation.
        var rejectWhole: Bool
    }

    static let maxSteps = 3
    static let minSteps = 2

    static func recommendation(from advice: ModelAdvice, context: AdviceContext) -> Recommendation {
        map(advice, context: context).recommendation
    }

    static func map(
        _ advice: ModelAdvice, context: AdviceContext, limits: AdviceOutputLimits = AdviceOutputLimits()
    ) -> Outcome {
        let (cleaned, findings) = AdviceOutputChecker.check(advice, context: context, limits: limits)
        let offered = AdvicePromptBuilder.offeredActions(for: context)
        var steps: [Recommendation.Step] = []
        var used = Set<AdviceAction.ID>()

        for pick in cleaned.picks where steps.count < maxSteps {
            let id = pick.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let suggested = offered.first(where: { $0.action.id.rawValue == id }),
                !used.contains(suggested.action.id)
            else {
                continue
            }
            used.insert(suggested.action.id)
            steps.append(AdviceStepRules.step(for: suggested, why: pick.why))
        }
        var dropped = cleaned.picks.count - steps.count

        for id in AdviceActions.fallbackPriority where steps.count < minSteps && !used.contains(id) {
            guard let suggested = offered.first(where: { $0.action.id == id }) else { continue }
            used.insert(id)
            steps.append(AdviceStepRules.step(for: suggested, why: nil))
        }

        let paired = AdviceStepRules.ensuringExtensionStep(steps, offered: offered)
        // The fill above stops at two steps, so a replacement only ever removes a model pick.
        if paired.count == steps.count && paired != steps { dropped += 1 }
        steps = paired

        let noticed = cleaned.noticed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
        let summary = cleaned.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
            if dropped > 0 {
                logger.debug("Dropped \(dropped) of \(advice.picks.count) model picks")
            }
            for finding in findings {
                logger.debug("Check failed: \(String(describing: finding), privacy: .public)")
            }
        #endif

        return Outcome(
            recommendation: Recommendation(
                summary: summary.isEmpty ? RuleBasedRecommender.summary(for: context) : summary,
                noticed: Array(noticed),
                steps: steps,
                source: .foundationModel),
            droppedPicks: dropped,
            findings: findings,
            rejectWhole: findings.count > limits.maxFailedFields)
    }

    #if DEBUG
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")
    #endif
}
