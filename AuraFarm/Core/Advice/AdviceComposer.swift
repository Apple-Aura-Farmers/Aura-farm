import Foundation

/// Puts the soil measurement steps beside the microscope steps, so "What to do next" shows both
/// together. The model and the standard advice only choose microscope and general steps. The
/// rules add every step the soil measurements call for, so a full list never pushes them out.
///
/// Pure and idempotent: composing an already composed recommendation gives the same result.
///
/// PROVISIONAL: the order and the cap are for the team to review.
enum AdviceComposer {
    /// How many soil steps are shown.
    static let maxSoilSteps = 5

    /// Said once in the summary when every recorded measurement is in its standard range.
    static let soilAllGood =
        "Your soil measurements are all in the standard range, so you can keep doing what you are doing now."

    static func combined(_ recommendation: Recommendation, context: AdviceContext) -> Recommendation {
        guard context.estimate.level != .notCounted else { return recommendation }
        var recommendation = recommendation
        if let readings = SoilInputs(context.result.soil)?.readings,
            readings.allSatisfy({ $0.band == .standard }),
            context.result.soil?.fertilizerType?.tone != .watch,
            !recommendation.summary.contains(soilAllGood)
        {
            recommendation.summary += " " + soilAllGood
        }

        func rank(_ id: AdviceAction.ID) -> Int {
            AdviceActions.fallbackPriority.firstIndex(of: id) ?? Int.max
        }
        let soilOnly = context.actions
            .filter { $0.fromSoil && !$0.fromMicroscope }
            .sorted { rank($0.action.id) < rank($1.action.id) }
            .prefix(maxSoilSteps)
        let soilOnlyIDs = Set(soilOnly.map(\.action.id))
        let both = Set(context.actions.filter { $0.fromSoil && $0.fromMicroscope }.map(\.action.id))

        // With nothing from the soil there is nothing to group, and the steps stay exactly as they
        // were written. A step the soil also supports still says so.
        guard !soilOnly.isEmpty else {
            var result = recommendation
            result.steps = recommendation.steps.map { step in
                var step = step
                step.alsoFromSoil = step.actionID.map(both.contains) ?? false
                return step
            }
            return result
        }

        var microscope: [Recommendation.Step] = []
        var extensionInSoil: Recommendation.Step?
        var modelWording: [AdviceAction.ID: Recommendation.Step] = [:]
        for var step in recommendation.steps {
            if let id = step.actionID, soilOnlyIDs.contains(id) {
                modelWording[id] = step
                continue
            }
            // The extension officer step this composer put last in the soil group stays there when
            // the advice is composed again.
            if step.actionID == .talkExtension, step.group == .soil {
                extensionInSoil = step
                continue
            }
            step.group = .microscope
            step.alsoFromSoil = step.actionID.map(both.contains) ?? false
            microscope.append(step)
        }

        var soil: [Recommendation.Step] = soilOnly.map { suggested in
            var step =
                modelWording[suggested.action.id]
                ?? AdviceStepRules.step(for: suggested, why: nil)
            step.group = .soil
            step.alsoFromSoil = false
            return step
        }

        // A step that needs an expert brings the extension officer, once.
        let all = microscope + soil
        let hasExtension = all.contains { $0.actionID == .talkExtension } || extensionInSoil != nil
        let needsExpert = all.contains { $0.actionID.flatMap(AdviceActions.action)?.review == .must }
        if needsExpert, !hasExtension,
            let extra = context.actions.first(where: { $0.action.id == .talkExtension })
        {
            var step = AdviceStepRules.step(for: extra, why: nil)
            step.group = .soil
            soil.append(step)
        } else if let extensionInSoil, needsExpert {
            soil.append(extensionInSoil)
        }

        var result = recommendation
        result.steps = microscope + soil
        return result
    }
}
