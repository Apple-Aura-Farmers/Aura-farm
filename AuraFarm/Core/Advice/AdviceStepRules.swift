import Foundation

/// How a suggested action becomes a step on screen, and the one rule that adds a step.
///
/// The rules mirror `docs/advice-content.md` (the team's "Advice content", approved
/// 9 November 2026). Change them in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum AdviceStepRules {
    /// The step for an action: the approved wording and timing, and the given reason, or the
    /// approved one when there is none.
    static func step(for suggested: AdviceContext.SuggestedAction, why: String?) -> Recommendation.Step {
        let own = why?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Recommendation.Step(
            actionID: suggested.action.id,
            text: suggested.action.wording,
            why: own.isEmpty ? suggested.reason : own,
            timing: suggested.action.timing)
    }

    /// Pairs an action marked must-check with "talk to your extension officer", which always
    /// goes last. With room it is appended. With three steps, the least relevant step that is
    /// neither a resample the sample itself calls for nor the last must-check action is dropped
    /// first, "least relevant" meaning furthest down `AdviceActions.fallbackPriority` (a step
    /// with no action counts as the least). Nothing changes when it isn't offered, is already
    /// there, or no step can be dropped.
    static func ensuringExtensionStep(
        _ steps: [Recommendation.Step], offered: [AdviceContext.SuggestedAction]
    ) -> [Recommendation.Step] {
        guard steps.contains(where: isMustCheck),
            !steps.contains(where: { $0.actionID == .talkExtension }),
            let extra = offered.first(where: { $0.action.id == .talkExtension })
        else { return steps }

        let added = step(for: extra, why: nil)
        if steps.count < AdviceResponseMapper.maxSteps { return steps + [added] }

        let protected: [AdviceAction.ID?] = [.resampleFresh, .resampleTrust]
        func rank(_ step: Recommendation.Step) -> Int {
            step.actionID.flatMap { AdviceActions.fallbackPriority.firstIndex(of: $0) } ?? Int.max
        }
        let candidates = steps.indices
            .filter { !protected.contains(steps[$0].actionID) }
            .sorted { rank(steps[$0]) > rank(steps[$1]) }
        for index in candidates {
            var remaining = steps
            remaining.remove(at: index)
            if remaining.contains(where: isMustCheck) { return remaining + [added] }
        }
        return steps
    }

    private static func isMustCheck(_ step: Recommendation.Step) -> Bool {
        step.actionID.flatMap { AdviceActions.action($0) }?.review == .must
    }
}
