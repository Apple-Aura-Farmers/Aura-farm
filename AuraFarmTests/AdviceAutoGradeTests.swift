import XCTest

@testable import AuraFarm

final class AdviceAutoGradeTests: XCTestCase {
    /// Euglenoids dominant, fair: refresh_water, review_fertilizer and talk_extension are on offer.
    private let context: AdviceContext = {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 10, moisture: .flooded,
            countsByClass: ["euglena": 10, "paramecium": 1], sweep: nil)
        let estimate = SoilHealthEstimate(
            level: .fair, score: nil, confidence: .low, reasons: [], followUp: "")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }()

    private func advice(
        noticed: [String] = ["Many Euglena were seen."],
        picks: [(String, String)] = [
            ("refresh_water", "Euglena often goes with still water."),
            ("review_fertilizer", "This was seen soon after fertilizing."),
        ],
        summary: String = "Lots of Euglena were seen, so the water may be rich in nutrients."
    ) -> ModelAdvice {
        ModelAdvice(
            noticed: noticed, picks: picks.map { ModelAdvice.Pick(id: $0.0, why: $0.1) }, summary: summary)
    }

    private func grade(_ advice: ModelAdvice, seconds: Double = 3) -> AdviceAutoGrade {
        AdviceAutoGrade.grade(
            advice: advice, outcome: AdviceResponseMapper.map(advice, context: context), context: context,
            seconds: seconds)
    }

    func testACleanAnswerPasses() {
        XCTAssertEqual(grade(advice()), AdviceAutoGrade(verdict: .pass, notes: []))
    }

    func testRejectedAsAWholeFails() {
        let result = grade(advice(picks: [("refresh_water", "Add 20 kg.")], summary: "This is healthy."))

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertTrue(result.notes.contains("More than one part of the answer failed the app's checks."))
    }

    func testABannedWordFailsEvenWhenOnlyOnePartFailed() {
        let result = grade(advice(summary: "This soil is healthy."))

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertEqual(result.notes, ["It used a banned word."])
    }

    func testADoseFails() {
        let result = grade(
            advice(picks: [
                ("refresh_water", "Add 20 kg to be sure."), ("review_fertilizer", "Seen after fertilizing."),
            ]))

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertEqual(result.notes, ["It gave an amount or dose."])
    }

    func testMentioningAnOrganismItMustNotFails() {
        let result = grade(advice(noticed: ["Stentor was common."]))

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertTrue(result.notes.contains("It mentioned an organism it must not."))
    }

    func testFewerThanTwoOfItsOwnPicksFails() {
        let result = grade(advice(picks: [("refresh_water", "Euglena often goes with still water.")]))

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertEqual(result.notes, ["Fewer than 2 of its own picks could be used."])
    }

    func testPicksThatWereNotOfferedDoNotCountAsItsOwn() {
        let result = grade(
            advice(picks: [("water_more", "x"), ("add_compost", "y"), ("refresh_water", "z")]))

        XCTAssertEqual(result.verdict, .fail)
    }

    func testDroppedPicksWarn() {
        let result = grade(
            advice(picks: [
                ("refresh_water", "Euglena often goes with still water."),
                ("review_fertilizer", "This was seen soon after fertilizing."), ("water_more", "x"),
            ]))

        XCTAssertEqual(result.verdict, .warn)
        XCTAssertEqual(result.notes, ["Dropped 1 pick that couldn't be used."])
    }

    func testALongReasonWarns() {
        let long = Array(repeating: "word", count: 26).joined(separator: " ")
        let result = grade(
            advice(picks: [("refresh_water", long), ("review_fertilizer", "Seen after fertilizing.")]))

        XCTAssertEqual(result.verdict, .warn)
        XCTAssertEqual(result.notes, ["Part of the answer was too long."])
    }

    func testASummaryOverTheInstructionLimitWarnsEvenThoughTheCheckerAllowsIt() {
        let summary = Array(repeating: "plain", count: 30).joined(separator: " ")
        let result = grade(advice(summary: summary))

        XCTAssertEqual(result.verdict, .warn)
        XCTAssertEqual(result.notes, ["The summary is over 25 words."])
    }

    func testAReasonThatRepeatsTheActionWarns() {
        let result = grade(
            advice(picks: [
                ("refresh_water", "Try not to let water sit, as it says."),
                ("review_fertilizer", "This was seen soon after fertilizing."),
            ]))

        XCTAssertEqual(result.verdict, .warn)
        XCTAssertEqual(result.notes, ["A reason repeats the action's words instead of explaining it."])
    }

    func testNothingNoticedWarns() {
        let result = grade(advice(noticed: []))

        XCTAssertEqual(result.verdict, .warn)
        XCTAssertEqual(result.notes, ["Nothing it noticed was kept."])
    }

    func testASlowAnswerWarns() {
        XCTAssertEqual(grade(advice(), seconds: AdviceEvalLimits.slowSeconds).verdict, .pass)
        let slow = grade(advice(), seconds: 20)

        XCTAssertEqual(slow.verdict, .warn)
        XCTAssertEqual(slow.notes, ["It took 20 seconds."])
    }

    func testFailuresComeBeforeWarningsAndSetTheVerdict() {
        let result = grade(advice(noticed: [], summary: "This is healthy."), seconds: 30)

        XCTAssertEqual(result.verdict, .fail)
        XCTAssertEqual(result.notes.first, "It used a banned word.")
        XCTAssertTrue(result.notes.contains("It took 30 seconds."))
    }
}
