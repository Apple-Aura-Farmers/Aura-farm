import XCTest

@testable import AuraFarm

final class AdviceEvalCSVTests: XCTestCase {
    private func recommendation(summary: String = "Summary.", steps: Int = 2) -> Recommendation {
        Recommendation(
            summary: summary, noticed: ["One", "Two"],
            steps: (0..<steps).map {
                Recommendation.Step(
                    actionID: .keepNotes, text: "Do thing \($0), then rest.", why: "Because \"\($0)\".",
                    timing: "Now")
            },
            source: .foundationModel)
    }

    private let model = AdviceEvalResult(
        caseID: "good-varied", title: "Plenty of life", level: .good, modelAsked: true, source: .model,
        seconds: 3.456, grade: AdviceAutoGrade(verdict: .warn, notes: ["It was slow.", "Too long."]),
        recommendation: nil, errorMessage: nil)

    private func parsed(_ results: [AdviceEvalResult]) -> [[String]] {
        CSVTests.parse(AdviceEvalCSV.csv(results: results, appVersion: "1.2"))
    }

    func testThereAre26ColumnsAndEveryRowHasThemAll() {
        var withAdvice = model
        withAdvice.recommendation = recommendation(steps: 3)
        var withoutSteps = model
        withoutSteps.recommendation = recommendation(steps: 0)
        let rows = parsed([withAdvice, withoutSteps, model])

        XCTAssertEqual(AdviceEvalCSV.columns.count, 26)
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows.allSatisfy { $0.count == 26 }, "\(rows.map(\.count))")
        XCTAssertEqual(rows[0], AdviceEvalCSV.columns)
    }

    func testAModelRowCarriesTheAnswerAndTheGrade() throws {
        var result = model
        result.recommendation = recommendation(summary: "Plenty, with commas, and \"quotes\".")
        let row = try XCTUnwrap(parsed([result]).last)
        let columns = AdviceEvalCSV.columns

        func value(_ name: String) -> String { row[columns.firstIndex(of: name) ?? 0] }
        XCTAssertEqual(value("case_id"), "good-varied")
        XCTAssertEqual(value("level"), "good")
        XCTAssertEqual(value("model_asked"), "yes")
        XCTAssertEqual(value("source"), "model")
        XCTAssertEqual(value("seconds"), "3.5")
        XCTAssertEqual(value("auto_verdict"), "warn")
        XCTAssertEqual(value("auto_notes"), "It was slow. Too long.")
        XCTAssertEqual(value("summary"), "Plenty, with commas, and \"quotes\".")
        XCTAssertEqual(value("noticed"), "One | Two")
        XCTAssertEqual(value("step1_id"), "keep_notes")
        XCTAssertEqual(value("step1_text"), "Do thing 0, then rest.")
        XCTAssertEqual(value("step1_why"), "Because \"0\".")
        XCTAssertEqual(value("step3_id"), "")
        XCTAssertEqual(value("content_version"), AdviceContentVersion.current)
        XCTAssertEqual(value("app_version"), "1.2")
    }

    func testTheScoringColumnsAreLeftEmpty() throws {
        var result = model
        result.recommendation = recommendation()
        let row = try XCTUnwrap(parsed([result]).last)

        XCTAssertEqual(
            Array(AdviceEvalCSV.columns.suffix(5)),
            [
                "accurate_1to3", "cautious_1to3", "practical_1to3", "readable_1to3", "reviewer_notes",
            ])
        XCTAssertEqual(Array(row.suffix(5)), ["", "", "", "", ""])
    }

    func testStandardAdviceRowsHaveNoVerdictOrSeconds() throws {
        let result = AdviceEvalResult(
            caseID: "too-few", title: "Too few to say", level: .tooFewToSay, modelAsked: false,
            source: .rules,
            seconds: nil, grade: nil, recommendation: recommendation(), errorMessage: nil)
        let row = try XCTUnwrap(parsed([result]).last)
        let columns = AdviceEvalCSV.columns

        XCTAssertEqual(row[columns.firstIndex(of: "source") ?? 0], "rules")
        XCTAssertEqual(row[columns.firstIndex(of: "model_asked") ?? 0], "no")
        XCTAssertEqual(row[columns.firstIndex(of: "auto_verdict") ?? 0], "")
        XCTAssertEqual(row[columns.firstIndex(of: "seconds") ?? 0], "")
        XCTAssertEqual(row[columns.firstIndex(of: "step1_text") ?? 0], "Do thing 0, then rest.")
    }

    func testAnErrorRowHasTheMessageInTheNotes() throws {
        let result = AdviceEvalResult(
            caseID: "fair-ordinary", title: "Some life", level: .fair, modelAsked: true, source: .error,
            seconds: nil, grade: nil, recommendation: nil,
            errorMessage: "Apple Intelligence is busy, try later.")
        let row = try XCTUnwrap(parsed([result]).last)
        let columns = AdviceEvalCSV.columns

        XCTAssertEqual(row[columns.firstIndex(of: "source") ?? 0], "error")
        XCTAssertEqual(
            row[columns.firstIndex(of: "auto_notes") ?? 0], "Apple Intelligence is busy, try later.")
        XCTAssertEqual(row.count, 26)
    }
}
