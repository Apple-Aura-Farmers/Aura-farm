import Foundation

/// One fixed sample in the advice test set, with what the advice must and must not do for it.
///
/// The set checks the rules (which actions are offered, which patterns match), not whether the
/// advice is right for the soil. PROVISIONAL: written for the prototype, not by an agronomist.
struct AdviceEvalCase: Identifiable, Equatable {
    /// Short, kebab-case, unique.
    var id: String
    /// Plain words for the screen.
    var title: String
    /// Never has a sweep.
    var result: SoilResult
    var history: [PastResult]
    var expectedLevel: SoilHealthEstimate.Level
    var mustMatch: Set<AdvicePattern>
    var mustNotMatch: Set<AdvicePattern>
    /// Checked against `AdvicePromptBuilder.offeredActions`.
    var mustOffer: Set<AdviceAction.ID>
    var mustNotOffer: Set<AdviceAction.ID>

    /// The model is only asked about good, fair and poor results.
    var modelAsked: Bool { [.good, .fair, .poor].contains(expectedLevel) }
}
