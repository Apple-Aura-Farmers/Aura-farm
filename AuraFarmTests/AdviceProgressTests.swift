import XCTest

@testable import AuraFarm

final class AdviceProgressTests: XCTestCase {
    func testWhereAPartlyWrittenAnswerIs() {
        XCTAssertEqual(AdviceProgress.from(actionCount: 0, hasSummary: false), .noticing)
        XCTAssertEqual(AdviceProgress.from(actionCount: 0, hasSummary: false), .noticing)
        XCTAssertEqual(
            AdviceProgress.from(actionCount: 1, hasSummary: false), .choosingSteps(chosen: 1)
        )
        XCTAssertEqual(
            AdviceProgress.from(actionCount: 3, hasSummary: false), .choosingSteps(chosen: 3)
        )
        XCTAssertEqual(AdviceProgress.from(actionCount: 3, hasSummary: true), .summarizing)
        XCTAssertEqual(AdviceProgress.from(actionCount: 0, hasSummary: true), .summarizing)
    }

    func testTheWordsOnTheCard() {
        XCTAssertEqual(AdviceProgress.noticing.message, "Looking at the sample…")
        XCTAssertEqual(AdviceProgress.choosingSteps(chosen: 0).message, "Choosing steps…")
        XCTAssertEqual(AdviceProgress.choosingSteps(chosen: 2).message, "Choosing steps (2 of 3)…")
        XCTAssertEqual(AdviceProgress.summarizing.message, "Writing a summary…")
    }
}
