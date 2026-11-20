import Foundation

/// Where the model is while it writes, so the card can say so. Worked out from a partly
/// written answer; the partial text itself is never shown.
enum AdviceProgress: Equatable {
    case noticing
    /// How many steps have been started so far.
    case choosingSteps(chosen: Int)
    case summarizing

    /// The words on the card while the model writes.
    var message: String {
        switch self {
        case .noticing: return String(localized: "Looking at the sample…")
        case .choosingSteps(let chosen):
            return chosen == 0 ? String(localized: "Choosing steps…") : String(localized: "Choosing steps (\(chosen) of 3)…")
        case .summarizing: return String(localized: "Writing a summary…")
        }
    }

    /// The model writes what it noticed, then the steps, then the summary, in that order.
    static func from(actionCount: Int, hasSummary: Bool) -> AdviceProgress {
        if hasSummary { return .summarizing }
        if actionCount > 0 { return .choosingSteps(chosen: actionCount) }
        return .noticing
    }
}
