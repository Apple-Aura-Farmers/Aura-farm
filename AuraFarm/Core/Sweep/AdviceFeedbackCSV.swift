import Foundation

/// The helpers' feedback as a spreadsheet, one row per piece of feedback.
enum AdviceFeedbackCSV {
    static let columns: [String] = [
        "sample_id", "recorded_at", "given_at", "rating", "reasons", "source", "content_version",
        "app_version", "summary", "step1_id", "step1_why", "step2_id", "step2_why", "step3_id", "step3_why",
    ]

    static func csv(records: [AdviceFeedbackRecord]) -> String {
        CSV.document(header: columns, rows: records.map(row))
    }

    private static func row(_ record: AdviceFeedbackRecord) -> [String] {
        let feedback = record.feedback
        var fields = [
            record.sampleID, timestamp(record.recordedAt), timestamp(feedback.givenAt),
            feedback.rating.rawValue,
            feedback.reasons.map(\.rawValue).joined(separator: " | "), feedback.source.rawValue,
            feedback.contentVersion, feedback.appVersion ?? "", feedback.recommendation.summary,
        ]
        let steps = feedback.recommendation.steps
        for step in (steps.map(Optional.some) + [nil, nil, nil]).prefix(3) {
            fields += [step?.actionID?.rawValue ?? "", step?.why ?? ""]
        }
        return fields
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
