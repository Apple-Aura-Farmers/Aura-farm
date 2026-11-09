import XCTest

@testable import AuraFarm

final class AdviceFeedbackTests: XCTestCase {
    private func feedback(
        _ rating: AdviceFeedback.Rating, reasons: [AdviceFeedback.Reason] = [], steps: Int = 2,
        source: Recommendation.Source = .foundationModel, summary: String = "Summary, with a comma."
    ) -> AdviceFeedback {
        AdviceFeedback(
            id: UUID(), givenAt: Date(timeIntervalSince1970: 1_800_000_000), rating: rating, reasons: reasons,
            source: source,
            recommendation: Recommendation(
                summary: summary, noticed: [],
                steps: (0..<steps).map {
                    Recommendation.Step(
                        actionID: .keepNotes, text: "Do \($0).", why: "Why \($0).", timing: nil)
                },
                source: source),
            contentVersion: "content-abc", appVersion: "1.0")
    }

    private func record(_ feedback: AdviceFeedback, sweep: String = "A12_f001") -> AdviceFeedbackRecord {
        AdviceFeedbackRecord(
            sweepName: sweep, sampleID: "A12", recordedAt: Date(timeIntervalSince1970: 1_793_000_000),
            feedback: feedback)
    }

    func testReasonLabels() {
        XCTAssertEqual(
            AdviceFeedback.Reason.allCases.map(\.label),
            ["Doesn't fit this field", "Hard to understand", "Seems wrong", "Unsafe or risky", "Other"])
    }

    func testFeedbackSurvivesARoundTrip() throws {
        let original = feedback(.notUseful, reasons: [.seemsWrong, .unsafe])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(try decoder.decode(AdviceFeedback.self, from: encoder.encode(original)), original)
    }

    func testTheSummaryCountsSweepsRatingsAndReasons() {
        let records = [
            record(feedback(.useful), sweep: "one"),
            record(feedback(.notUseful, reasons: [.doesNotFit]), sweep: "one"),
            record(feedback(.notUseful, reasons: [.doesNotFit, .unsafe]), sweep: "two"),
        ]

        let summary = AdviceFeedbackSummary(records: records)

        XCTAssertEqual(summary.sweepCount, 2)
        XCTAssertEqual(summary.useful, 1)
        XCTAssertEqual(summary.notUseful, 2)
        XCTAssertEqual(summary.perReason, [.doesNotFit: 2, .unsafe: 1])
        XCTAssertEqual(AdviceFeedbackSummary(records: []), AdviceFeedbackSummary(records: []))
        XCTAssertEqual(AdviceFeedbackSummary(records: []).sweepCount, 0)
    }

    func testTheCSVHas15ColumnsAndQuotesWhatNeedsIt() throws {
        let records = [
            record(feedback(.notUseful, reasons: [.doesNotFit, .other])),
            record(feedback(.useful, steps: 0, source: .rules)),
        ]
        let rows = CSVTests.parse(AdviceFeedbackCSV.csv(records: records))

        XCTAssertEqual(AdviceFeedbackCSV.columns.count, 15)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.count == 15 }, "\(rows.map(\.count))")
        XCTAssertEqual(rows[0], AdviceFeedbackCSV.columns)

        let columns = AdviceFeedbackCSV.columns
        func value(_ row: [String], _ name: String) -> String { row[columns.firstIndex(of: name) ?? 0] }
        XCTAssertEqual(value(rows[1], "sample_id"), "A12")
        XCTAssertEqual(value(rows[1], "rating"), "notUseful")
        XCTAssertEqual(value(rows[1], "reasons"), "doesNotFit | other")
        XCTAssertEqual(value(rows[1], "source"), "foundationModel")
        XCTAssertEqual(value(rows[1], "content_version"), "content-abc")
        XCTAssertEqual(value(rows[1], "summary"), "Summary, with a comma.")
        XCTAssertEqual(value(rows[1], "step1_id"), "keep_notes")
        XCTAssertEqual(value(rows[1], "step2_why"), "Why 1.")
        XCTAssertEqual(value(rows[1], "step3_id"), "")
        XCTAssertEqual(value(rows[2], "source"), "rules")
        XCTAssertEqual(value(rows[2], "step1_id"), "")
    }
}
