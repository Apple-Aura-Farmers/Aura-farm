import XCTest

@testable import AuraFarm

final class ReadingConsistencyTests: XCTestCase {
    private let box = 300.0  // 12% of it: 36 px

    func testAFalseJumpIsReplacedByThePrediction() {
        var check = ReadingConsistency()
        _ = check.judge(anchorOffset: CGPoint(x: 20, y: 0), frameShift: CGPoint(x: 20, y: 0), boxSide: box)
        let verdict = check.judge(
            anchorOffset: CGPoint(x: 250, y: 5), frameShift: CGPoint(x: 18, y: 1), boxSide: box)
        XCTAssertEqual(verdict, .predicted(CGPoint(x: 38, y: 1)))
        XCTAssertEqual(check.predictedStreak, 1)
    }

    func testARealGradualMoveIsMeasured() {
        var check = ReadingConsistency()
        var offset = CGPoint.zero
        for _ in 0..<8 {
            offset.x += 20
            // The anchor reading is a few px off the frame-to-frame sum, as real ones are.
            let verdict = check.judge(
                anchorOffset: CGPoint(x: offset.x + 3, y: -2), frameShift: CGPoint(x: 20, y: 0),
                boxSide: box)
            XCTAssertEqual(verdict, .measured(CGPoint(x: offset.x + 3, y: -2)))
            offset.x += 3
            offset.x -= 3
        }
        XCTAssertEqual(check.predictedStreak, 0)
    }

    func testNoAnchorReadingIsPredictedWhenTheShiftIsKnown() {
        var check = ReadingConsistency()
        XCTAssertEqual(
            check.judge(anchorOffset: nil, frameShift: CGPoint(x: 10, y: 0), boxSide: box),
            .predicted(CGPoint(x: 10, y: 0)))
    }

    func testMissingBothGivesMissing() {
        var check = ReadingConsistency()
        XCTAssertEqual(check.judge(anchorOffset: nil, frameShift: nil, boxSide: box), .missing)
        XCTAssertEqual(check.predictedStreak, 0)
    }

    func testAnAnchorReadingWithoutAShiftIsTakenAsMeasured() {
        var check = ReadingConsistency()
        XCTAssertEqual(
            check.judge(anchorOffset: CGPoint(x: 9, y: 9), frameShift: nil, boxSide: box),
            .measured(CGPoint(x: 9, y: 9)))
    }

    func testTheStreakAsksForACommitAfterTheLimitAndAMeasuredReadingClearsIt() {
        var check = ReadingConsistency(
            thresholds: ReadingConsistencyThresholds(maxPredictedInARow: 3))
        for _ in 0..<2 {
            _ = check.judge(
                anchorOffset: CGPoint(x: 400, y: 0), frameShift: CGPoint(x: 5, y: 0), boxSide: box)
            XCTAssertFalse(check.mustCommit)
        }
        _ = check.judge(anchorOffset: CGPoint(x: 400, y: 0), frameShift: CGPoint(x: 5, y: 0), boxSide: box)
        XCTAssertTrue(check.mustCommit)
        XCTAssertEqual(check.lastAccepted.x, 15, accuracy: 0.001)

        var other = ReadingConsistency()
        _ = other.judge(anchorOffset: CGPoint(x: 400, y: 0), frameShift: CGPoint(x: 5, y: 0), boxSide: box)
        _ = other.judge(anchorOffset: CGPoint(x: 10, y: 0), frameShift: CGPoint(x: 5, y: 0), boxSide: box)
        XCTAssertEqual(other.predictedStreak, 0)
    }

    func testResetStartsFromZeroAgain() {
        var check = ReadingConsistency()
        _ = check.judge(anchorOffset: CGPoint(x: 30, y: 0), frameShift: CGPoint(x: 30, y: 0), boxSide: box)
        _ = check.judge(anchorOffset: CGPoint(x: 900, y: 0), frameShift: CGPoint(x: 1, y: 0), boxSide: box)
        check.reset()
        XCTAssertEqual(check.lastAccepted, .zero)
        XCTAssertEqual(check.predictedStreak, 0)
        XCTAssertEqual(
            check.judge(anchorOffset: CGPoint(x: 6, y: 0), frameShift: CGPoint(x: 6, y: 0), boxSide: box),
            .measured(CGPoint(x: 6, y: 0)))
    }

    func testVerdictNamesAndOffsets() {
        XCTAssertEqual(ReadingVerdict.measured(.zero).csvName, "measured")
        XCTAssertEqual(ReadingVerdict.predicted(.zero).csvName, "predicted")
        XCTAssertEqual(ReadingVerdict.missing.csvName, "missing")
        XCTAssertNil(ReadingVerdict.missing.offset)
    }
}

final class DetailCheckTests: XCTestCase {
    func testDetailGoesAfterTheStreakAndComesBackAfterTheStreak() {
        var check = DetailCheck()
        let low = DetailThresholds().minBoxSharpness - 1
        let high = DetailThresholds().minBoxSharpness + 1
        check.update(boxSharpness: low)
        check.update(boxSharpness: low)
        XCTAssertTrue(check.hasDetail, "two low readings are not enough")
        check.update(boxSharpness: high)
        check.update(boxSharpness: low)
        check.update(boxSharpness: low)
        XCTAssertTrue(check.hasDetail, "a good reading breaks the streak")
        check.update(boxSharpness: low)
        XCTAssertFalse(check.hasDetail)

        check.update(boxSharpness: high)
        check.update(boxSharpness: high)
        check.update(boxSharpness: low)
        check.update(boxSharpness: high)
        check.update(boxSharpness: high)
        XCTAssertFalse(check.hasDetail, "the streak back was broken")
        check.update(boxSharpness: high)
        XCTAssertTrue(check.hasDetail)
    }

    func testResetHasDetail() {
        var check = DetailCheck()
        for _ in 0..<3 { check.update(boxSharpness: 0) }
        XCTAssertFalse(check.hasDetail)
        check.reset()
        XCTAssertTrue(check.hasDetail)
    }
}

final class HopOdometerPauseTests: XCTestCase {
    private let frame = CGSize(width: 1280, height: 720)

    func testCommitCountsAHopWhateverItsSizeAndKeepsThePosition() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: CGPoint(x: 10, y: 0), frameSize: frame, referenceSide: 300)
        odometer.commit(offset: CGPoint(x: 30, y: 0))
        XCTAssertEqual(odometer.hops, 1)
        XCTAssertEqual(odometer.position.x, 30, accuracy: 0.001)
        XCTAssertEqual(odometer.live, .zero)
    }

    func testRebaseFoldsTheLiveOffsetInWithoutAHop() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: CGPoint(x: 40, y: 3), frameSize: frame, referenceSide: 400)
        odometer.rebase()
        XCTAssertEqual(odometer.hops, 0)
        XCTAssertEqual(odometer.position.x, 40, accuracy: 0.001)
        XCTAssertEqual(odometer.live, .zero)
        _ = odometer.update(offset: CGPoint(x: 10, y: 0), frameSize: frame, referenceSide: 400)
        XCTAssertEqual(odometer.position.x, 50, accuracy: 0.001)
    }

    func testNoDetailStatusOverridesTheRest() {
        var indicators = MovementIndicators()
        indicators.update(
            shake: CGPoint(x: 1, y: 0), anchorOffset: nil, positionFields: .zero, isLost: true,
            event: .none, referenceSide: 300, seconds: 0, hopDistance: 75, hasDetail: false)
        XCTAssertEqual(indicators.status, .noDetail)
        XCTAssertEqual(MovementIndicators.Status.noDetail.csvName, "no_detail")
        indicators.update(
            shake: CGPoint(x: 1, y: 0), anchorOffset: nil, positionFields: .zero, isLost: false,
            event: .none, referenceSide: 300, seconds: 0.1, hopDistance: 75)
        XCTAssertEqual(indicators.status, .tracking)
    }
}
