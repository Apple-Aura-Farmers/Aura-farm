import Foundation

/// The totals shown above the feedback export.
struct AdviceFeedbackSummary: Equatable {
    var sweepCount = 0
    var useful = 0
    var notUseful = 0
    var perReason: [AdviceFeedback.Reason: Int] = [:]

    init(records: [AdviceFeedbackRecord]) {
        sweepCount = Set(records.map(\.sweepName)).count
        for record in records {
            switch record.feedback.rating {
            case .useful: useful += 1
            case .notUseful: notUseful += 1
            }
            for reason in record.feedback.reasons { perReason[reason, default: 0] += 1 }
        }
    }
}
