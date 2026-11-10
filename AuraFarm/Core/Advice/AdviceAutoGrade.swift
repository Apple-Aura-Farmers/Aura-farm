import Foundation

/// A quick, automatic grade of one model answer: how well it followed the app's rules. It
/// never says whether the advice is right for the soil; people score that in the exported
/// sheet.
///
/// PROVISIONAL: the rules are placeholders for the team to review.
struct AdviceAutoGrade: Equatable {
    enum Verdict: String, Equatable {
        case pass, warn, fail
    }

    var verdict: Verdict
    /// Plain sentences, one per problem.
    var notes: [String]

    static func grade(
        advice: ModelAdvice, outcome: AdviceResponseMapper.Outcome, context: AdviceContext, seconds: Double
    ) -> AdviceAutoGrade {
        var failures: [String] = []
        var warnings: [String] = []

        if outcome.rejectWhole {
            failures.append("More than one part of the answer failed the app's checks.")
        }
        let problems = outcome.findings.flatMap(\.problems)
        if problems.contains(where: { if case .bannedWord = $0 { return true } else { return false } }) {
            failures.append("It used a banned word.")
        }
        if problems.contains(where: { if case .dose = $0 { return true } else { return false } }) {
            failures.append("It gave an amount or dose.")
        }
        if problems.contains(where: {
            if case .uninterpretedOrganism = $0 { return true } else { return false }
        }) {
            failures.append("It mentioned an organism it must not.")
        }

        let offered = Set(AdvicePromptBuilder.offeredActions(for: context).map { $0.action.id.rawValue })
        var ownPicks = Set<String>()
        for pick in advice.picks {
            let id = pick.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if offered.contains(id) { ownPicks.insert(id) }
        }
        if min(ownPicks.count, AdviceResponseMapper.maxSteps) < AdviceResponseMapper.minSteps {
            failures.append("Fewer than 2 of its own picks could be used.")
        }

        if outcome.droppedPicks > 0 {
            let n = outcome.droppedPicks
            warnings.append("Dropped \(n) pick\(n == 1 ? "" : "s") that couldn't be used.")
        }
        if problems.contains(where: { if case .tooLong = $0 { return true } else { return false } }) {
            warnings.append("Part of the answer was too long.")
        }
        if wordCount(advice.summary) > AdviceEvalLimits.summaryWords {
            warnings.append("The summary is over \(AdviceEvalLimits.summaryWords) words.")
        }
        if outcome.recommendation.steps.contains(where: repeatsItsAction) {
            warnings.append("A reason repeats the action's words instead of explaining it.")
        }
        if outcome.recommendation.noticed.isEmpty { warnings.append("Nothing it noticed was kept.") }
        if seconds > AdviceEvalLimits.slowSeconds {
            warnings.append("It took \(Int(seconds.rounded())) seconds.")
        }

        let verdict: Verdict = !failures.isEmpty ? .fail : !warnings.isEmpty ? .warn : .pass
        return AdviceAutoGrade(verdict: verdict, notes: failures + warnings)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// True when the reason contains the first words of the action's own wording.
    private static func repeatsItsAction(_ step: Recommendation.Step) -> Bool {
        guard let why = step.why else { return false }
        let opening = step.text.split(whereSeparator: \.isWhitespace)
            .prefix(AdviceEvalLimits.repeatedWordingWords).joined(separator: " ")
        return !opening.isEmpty && why.range(of: opening, options: .caseInsensitive) != nil
    }
}
