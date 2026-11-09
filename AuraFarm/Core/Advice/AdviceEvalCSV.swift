import Foundation

/// The Advice check as a spreadsheet: one row per case, with empty columns for people to score
/// each answer.
enum AdviceEvalCSV {
    static let columns: [String] = [
        "case_id", "title", "level", "model_asked", "source", "seconds", "auto_verdict", "auto_notes",
        "summary", "noticed", "step1_id", "step1_text", "step1_why", "step2_id", "step2_text", "step2_why",
        "step3_id", "step3_text", "step3_why", "content_version", "app_version", "accurate_1to3",
        "cautious_1to3", "practical_1to3", "readable_1to3", "reviewer_notes",
    ]

    static func csv(results: [AdviceEvalResult], appVersion: String?) -> String {
        CSV.document(header: columns, rows: results.map { row($0, appVersion: appVersion) })
    }

    private static func row(_ result: AdviceEvalResult, appVersion: String?) -> [String] {
        let notes =
            result.source == .error
            ? (result.errorMessage ?? "") : (result.grade?.notes ?? []).joined(separator: " ")
        var fields = [
            result.caseID, result.title, result.level.rawValue, result.modelAsked ? "yes" : "no",
            result.source.rawValue, result.seconds.map { String(format: "%.1f", $0) } ?? "",
            result.grade?.verdict.rawValue ?? "", notes,
            result.recommendation?.summary ?? "",
            (result.recommendation?.noticed ?? []).joined(separator: " | "),
        ]
        let steps = result.recommendation?.steps ?? []
        for index in 0..<3 {
            if index < steps.count {
                fields += [steps[index].actionID?.rawValue ?? "", steps[index].text, steps[index].why ?? ""]
            } else {
                fields += ["", "", ""]
            }
        }
        fields += [AdviceContentVersion.current, appVersion ?? ""]
        // Left empty, for people to fill in.
        fields += ["", "", "", "", ""]
        return fields
    }
}
