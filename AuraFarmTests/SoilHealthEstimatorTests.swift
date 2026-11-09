import XCTest

@testable import AuraFarm

final class SoilHealthEstimatorTests: XCTestCase {
    private let estimator = PlaceholderSoilHealthEstimator()

    private func result(_ counts: [String: Int]?, frames: Int = 12) -> SoilResult {
        SoilResult(
            sampleID: "A12",
            recordedAt: .now,
            framesKept: frames,
            moisture: .flooded,
            countsByClass: counts,
            sweep: nil
        )
    }

    func testSweepThatWasNotCountedIsNotEstimated() {
        let estimate = estimator.estimate(result(nil))

        XCTAssertEqual(estimate.level, .notCounted)
        XCTAssertNil(estimate.score)
    }

    func testTooFewOrganismsIsTooFewToSayRatherThanPoor() {
        XCTAssertEqual(estimator.estimate(result([:])).level, .tooFewToSay)
        XCTAssertEqual(estimator.estimate(result(["euglena": 4])).level, .tooFewToSay)
        XCTAssertNotEqual(estimator.estimate(result(["euglena": 5])).level, .tooFewToSay)
    }

    func testPlentyOfEveryKindIsGood() {
        let counts = ["paramecium": 20, "euglena": 20, "vorticella": 20, "stentor": 20, "volvox": 20]
        let estimate = estimator.estimate(result(counts))

        XCTAssertEqual(estimate.level, .good)
        XCTAssertEqual(estimate.score, 100)
    }

    func testFewOfOneKindIsPoor() {
        XCTAssertEqual(estimator.estimate(result(["euglena": 7])).level, .poor)
    }

    func testMoreKindsScoreHigherForTheSameTotal() throws {
        let one = try XCTUnwrap(estimator.estimate(result(["euglena": 12])).score)
        let three = try XCTUnwrap(
            estimator.estimate(result(["euglena": 4, "paramecium": 4, "stentor": 4])).score)

        XCTAssertGreaterThan(three, one)
    }

    func testAbundanceIsReadPerFrameSoAShortSweepIsNotPenalised() {
        let counts = ["euglena": 12, "paramecium": 12]

        XCTAssertEqual(
            estimator.estimate(result(counts, frames: 6)).score,
            estimator.estimate(result(counts.mapValues { $0 * 2 }, frames: 12)).score
        )
    }

    func testLevelBoundariesFollowTheThresholds() {
        var thresholds = SoilHealthThresholds()
        thresholds.goodFrom = 50
        thresholds.fairFrom = 10
        let estimate = PlaceholderSoilHealthEstimator(thresholds: thresholds)
            .estimate(result(["euglena": 7]))

        XCTAssertEqual(estimate.level, .fair)
    }

    func testEveryEstimateSaysWhenToTestAgainAndIsLowConfidence() {
        for counts in [nil, [:], ["euglena": 7], ["euglena": 60, "paramecium": 60]] as [[String: Int]?] {
            let estimate = estimator.estimate(result(counts))
            XCTAssertFalse(estimate.followUp.isEmpty)
            XCTAssertFalse(estimate.reasons.isEmpty)
            XCTAssertEqual(estimate.confidence, .low)
        }
    }
}
