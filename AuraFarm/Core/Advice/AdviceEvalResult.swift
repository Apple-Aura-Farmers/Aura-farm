import Foundation

/// What one case of the Advice check came to, ready for the screen and the CSV.
struct AdviceEvalResult: Equatable {
    enum Source: String, Equatable {
        /// Written by the on-device model.
        case model
        /// Standard advice, because the model isn't asked about this case.
        case rules
        /// The model failed.
        case error
    }

    var caseID: String
    var title: String
    var level: SoilHealthEstimate.Level
    var modelAsked: Bool
    var source: Source
    /// nil for standard advice.
    var seconds: Double?
    /// nil for standard advice and errors.
    var grade: AdviceAutoGrade?
    var recommendation: Recommendation?
    /// For `.error`.
    var errorMessage: String?
}
