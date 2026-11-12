import XCTest

@testable import AuraFarm

final class PictureMatchTests: XCTestCase {
    private let box = 344.0

    func testASteadyCorrectChainConfirmsOnTheThirdReadingWithTheLatestOffset() {
        var check = PictureMatchCheck()
        let shift = CGPoint(x: 10, y: 0)
        XCTAssertEqual(check.feed(offset: CGPoint(x: 100, y: 5), frameShift: shift, boxSide: box), .pending)
        XCTAssertEqual(check.feed(offset: CGPoint(x: 110, y: 5), frameShift: shift, boxSide: box), .pending)
        XCTAssertEqual(
            check.feed(offset: CGPoint(x: 120, y: 5), frameShift: shift, boxSide: box),
            .confirmed(CGPoint(x: 120, y: 5)))
    }

    func testASingleFalseJumpInTheMiddleBreaksAndRestartsTheChain() {
        var check = PictureMatchCheck()
        let shift = CGPoint(x: 5, y: 0)
        _ = check.feed(offset: CGPoint(x: 100, y: 0), frameShift: shift, boxSide: box)
        _ = check.feed(offset: CGPoint(x: 105, y: 0), frameShift: shift, boxSide: box)
        // A false jump (still in range) restarts the chain from itself.
        XCTAssertEqual(check.feed(offset: CGPoint(x: -90, y: 0), frameShift: shift, boxSide: box), .pending)
        XCTAssertEqual(check.feed(offset: CGPoint(x: 110, y: 0), frameShift: shift, boxSide: box), .pending)
        XCTAssertEqual(check.feed(offset: CGPoint(x: 115, y: 0), frameShift: shift, boxSide: box), .pending)
        XCTAssertEqual(
            check.feed(offset: CGPoint(x: 120, y: 0), frameShift: shift, boxSide: box),
            .confirmed(CGPoint(x: 120, y: 0)))
    }

    func testOutOfRangeAndMissingReadingsNeverConfirmAndEndInRejected() {
        var check = PictureMatchCheck()
        let limit = check.thresholds.maxReadings
        var verdict = PictureMatchVerdict.pending
        for index in 0..<limit {
            // 0.4 of 344 is 137.6: 200 is out of range, and every other reading is missing.
            let offset: CGPoint? = index.isMultiple(of: 2) ? CGPoint(x: 200, y: 0) : nil
            verdict = check.feed(offset: offset, frameShift: .zero, boxSide: box)
            if index < limit - 1 { XCTAssertEqual(verdict, .pending) }
        }
        XCTAssertEqual(verdict, .rejected)
    }

    func testNoFrameShiftMeansSteadyOffsetsConfirm() {
        var check = PictureMatchCheck()
        var verdict = PictureMatchVerdict.pending
        for _ in 0..<3 {
            verdict = check.feed(offset: CGPoint(x: 40, y: -20), frameShift: nil, boxSide: box)
        }
        XCTAssertEqual(verdict, .confirmed(CGPoint(x: 40, y: -20)))
    }

    func testTheVerdictIsStickyUntilReset() {
        var check = PictureMatchCheck()
        for _ in 0..<3 { _ = check.feed(offset: CGPoint(x: 5, y: 5), frameShift: nil, boxSide: box) }
        XCTAssertEqual(
            check.feed(offset: nil, frameShift: nil, boxSide: box), .confirmed(CGPoint(x: 5, y: 5)))
        XCTAssertEqual(
            check.feed(offset: CGPoint(x: 99, y: 0), frameShift: nil, boxSide: box),
            .confirmed(CGPoint(x: 5, y: 5)))
        check.reset()
        XCTAssertEqual(check.feed(offset: CGPoint(x: 1, y: 1), frameShift: nil, boxSide: box), .pending)

        var rejecting = PictureMatchCheck()
        for _ in 0..<rejecting.thresholds.maxReadings {
            _ = rejecting.feed(offset: nil, frameShift: nil, boxSide: box)
        }
        XCTAssertEqual(rejecting.feed(offset: CGPoint(x: 1, y: 1), frameShift: nil, boxSide: box), .rejected)
    }

    func testAChainReadingJustWithinTheStepLimitCounts() {
        var check = PictureMatchCheck()
        let limit = check.thresholds.maxStepDisagreementOfBox * box  // 17.2 px
        _ = check.feed(offset: CGPoint(x: 50, y: 0), frameShift: .zero, boxSide: box)
        _ = check.feed(offset: CGPoint(x: 50 + limit - 1, y: 0), frameShift: .zero, boxSide: box)
        XCTAssertEqual(
            check.feed(offset: CGPoint(x: 50 + limit - 1, y: 0), frameShift: .zero, boxSide: box),
            .confirmed(CGPoint(x: 50 + limit - 1, y: 0)))
    }

    func testResetToAnAcceptedOffsetStartsTheStreakAfresh() {
        var consistency = ReadingConsistency()
        _ = consistency.judge(
            anchorOffset: CGPoint(x: 400, y: 0), frameShift: CGPoint(x: 5, y: 0), boxSide: 300)
        XCTAssertEqual(consistency.predictedStreak, 1)
        consistency.reset(to: CGPoint(x: 60, y: -4))
        XCTAssertEqual(consistency.lastAccepted, CGPoint(x: 60, y: -4))
        XCTAssertEqual(consistency.predictedStreak, 0)
        XCTAssertEqual(
            consistency.judge(
                anchorOffset: CGPoint(x: 70, y: -4), frameShift: CGPoint(x: 10, y: 0), boxSide: 300),
            .measured(CGPoint(x: 70, y: -4)))
    }
}
