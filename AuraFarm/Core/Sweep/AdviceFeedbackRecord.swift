import Foundation

/// One piece of feedback with the sample it was given on, for the feedback export.
struct AdviceFeedbackRecord: Equatable {
    /// The sweep's folder name, which tells sweeps apart.
    var sweepName: String
    var sampleID: String
    var recordedAt: Date
    var feedback: AdviceFeedback
}
