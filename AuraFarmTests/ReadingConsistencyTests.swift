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

    // MARK: Phase 2m: the chain since the anchor

    private let boxSide = 322.0

    /// Replays logged rows the way the tracker uses `ReadingConsistency`: a hop (the CSV's, or a
    /// forced commit after the predicted streak) adds the used offset to the total and re-anchors.
    private func replay(
        shakeX: [Double], shakeY: [Double], anchorX: [Double], anchorY: [Double],
        start: (x: Double, y: Double), hops: Set<Int> = [],
        thresholds: ReadingConsistencyThresholds = ReadingConsistencyThresholds()
    ) -> (moved: CGPoint, measured: Int, rows: Int) {
        var check = ReadingConsistency(thresholds: thresholds)
        check.reset(to: CGPoint(x: start.x, y: start.y))
        var total = CGPoint.zero
        var used = CGPoint(x: start.x, y: start.y)
        var measured = 0
        for index in shakeX.indices {
            let verdict = check.judge(
                anchorOffset: CGPoint(x: anchorX[index], y: anchorY[index]),
                frameShift: CGPoint(x: shakeX[index], y: shakeY[index]), boxSide: boxSide)
            used = verdict.offset ?? used
            var commit = hops.contains(index)
            if case .measured = verdict { measured += 1 }
            if case .predicted = verdict, check.mustCommit { commit = true }
            if commit {
                total = CGPoint(x: total.x + used.x, y: total.y + used.y)
                used = .zero
                check.reset()
            }
        }
        return (
            CGPoint(x: total.x + used.x - start.x, y: total.y + used.y - start.y), measured,
            shakeX.count
        )
    }

    private func stuckReplay(
        _ thresholds: ReadingConsistencyThresholds = ReadingConsistencyThresholds()
    ) -> (moved: CGPoint, measured: Int, rows: Int) {
        typealias Rows = Free20261116Fixture
        return replay(
            shakeX: Rows.stuckShakeX, shakeY: Rows.stuckShakeY, anchorX: Rows.stuckAnchorX,
            anchorY: Rows.stuckAnchorY, start: Rows.stuckStart, thresholds: thresholds)
    }

    func testTheStuckAnchorRunOfThe16thKeepsTheMoveItLostBefore() {
        // 5.9 to 13.0 s: the frame-to-frame shifts add up to 468 px in y (about 450); the old rule
        // let the stuck anchor win every frame and kept 30 px.
        var old = ReadingConsistencyThresholds()
        old.chainToleranceBasePx = 1e9  // the chain check switched off: today's behaviour
        let before = stuckReplay(old)
        let now = stuckReplay()
        print("stuck window: before \(before.moved.y) px, now \(now.moved.y) px of 468")
        XCTAssertLessThan(before.moved.y, 100)
        XCTAssertEqual(now.moved.y, 450, accuracy: 45)
    }

    func testTheLaterRunWhereTheAnchorWorkedStillMatchesTheCSVPosition() {
        // 23.2 to 29.0 s: chain and anchor agree, so nothing is lost and most readings stay measured.
        typealias Rows = Free20261116Fixture
        let result = replay(
            shakeX: Rows.laterShakeX, shakeY: Rows.laterShakeY, anchorX: Rows.laterAnchorX,
            anchorY: Rows.laterAnchorY, start: Rows.laterStart, hops: Rows.laterHops)
        print("later window: moved \(result.moved), measured \(result.measured) of \(result.rows)")
        XCTAssertEqual(result.moved.y, 539, accuracy: 3)
        // x: the CSV's own frame-to-frame sum is -74 against its position change of -71.
        XCTAssertEqual(result.moved.x, -71, accuracy: 5)
        XCTAssertGreaterThan(Double(result.measured) / Double(result.rows), 0.6)
    }

    func testASlowMoveWithTheAnchorStuckAtZeroTurnsPredictedAndKeepsTheMove() {
        var check = ReadingConsistency()
        var verdicts: [ReadingVerdict] = []
        for _ in 0..<12 {
            verdicts.append(
                check.judge(anchorOffset: .zero, frameShift: CGPoint(x: 0, y: 3), boxSide: boxSide))
        }
        // 3 px a frame: the gap (3 k) passes 6 + 0.1 x 3 k at the third frame.
        XCTAssertEqual(verdicts[0], .measured(.zero))
        XCTAssertEqual(verdicts[1], .measured(.zero))
        XCTAssertEqual(verdicts[2], .predicted(CGPoint(x: 0, y: 9)))
        XCTAssertEqual(verdicts[3], .predicted(CGPoint(x: 0, y: 12)))
        XCTAssertEqual(check.chain, CGPoint(x: 0, y: 36))
        let rows = Array(repeating: 3.0, count: 40)
        let moved = replay(
            shakeX: Array(repeating: 0, count: 40), shakeY: rows,
            anchorX: Array(repeating: 0, count: 40), anchorY: Array(repeating: 0, count: 40),
            start: (0, 0))
        XCTAssertEqual(moved.moved.y, 120, accuracy: 6)
    }

    func testTheChainIsNotPulledTowardTheAnchor() throws {
        var check = ReadingConsistency()
        for _ in 0..<10 {
            _ = check.judge(anchorOffset: .zero, frameShift: CGPoint(x: 0, y: 4), boxSide: boxSide)
        }
        XCTAssertEqual(check.chain, CGPoint(x: 0, y: 40))
        XCTAssertEqual(try XCTUnwrap(check.lastChainGap), 40, accuracy: 1e-9)
    }

    func testAMissingFrameShiftBreaksTheChainAndFallsBackToTheAnchor() {
        var check = ReadingConsistency()
        _ = check.judge(anchorOffset: CGPoint(x: 0, y: 4), frameShift: CGPoint(x: 0, y: 4), boxSide: boxSide)
        XCTAssertEqual(
            check.judge(anchorOffset: CGPoint(x: 0, y: 200), frameShift: nil, boxSide: boxSide),
            .measured(CGPoint(x: 0, y: 200)))
        XCTAssertNil(check.chain)
        // Until the next reset: today's per-frame rule alone.
        XCTAssertEqual(
            check.judge(
                anchorOffset: CGPoint(x: 0, y: 205), frameShift: CGPoint(x: 0, y: 5), boxSide: boxSide),
            .measured(CGPoint(x: 0, y: 205)))
        check.reset(to: CGPoint(x: 0, y: 10))
        XCTAssertEqual(check.chain, CGPoint(x: 0, y: 10))
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
