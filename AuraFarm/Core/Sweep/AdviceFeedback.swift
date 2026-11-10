import Foundation

/// A helper's verdict on one piece of advice, kept with the sample.
struct AdviceFeedback: Codable, Equatable, Identifiable {
    enum Rating: String, Codable, Equatable {
        case useful, notUseful
    }

    enum Reason: String, Codable, CaseIterable, Equatable {
        case doesNotFit, hardToUnderstand, seemsWrong, unsafe, other

        var label: String {
            switch self {
            case .doesNotFit: return "Doesn't fit this field"
            case .hardToUnderstand: return "Hard to understand"
            case .seemsWrong: return "Seems wrong"
            case .unsafe: return "Unsafe or risky"
            case .other: return "Other"
            }
        }
    }

    var id: UUID
    var givenAt: Date
    var rating: Rating
    var reasons: [Reason]
    var source: Recommendation.Source
    /// What was on screen when the helper rated it.
    var recommendation: Recommendation
    var contentVersion: String
    var appVersion: String?
}
