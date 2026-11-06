import CoreGraphics
import XCTest

@testable import AuraFarm

final class FrameSweepTests: XCTestCase {
    private let thresholds = SweepThresholds(
        framesPerSweep: 3,
        framesPerRow: 2,
        shiftBetweenFrames: 100,
        ignoreShiftBelow: 3,
        maxStepPixels: 150,
        maxBytes: 1_000
    )

    func testTheFirstFrameIsKeptAsSoonAsTheImageIsGood() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testNothingIsKeptUntilTheCheckHasSettled() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isSettled: false, issue: nil, shift: nil), .wait)
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.prompt, .fixTheImage)
    }

    func testBlurAndDarknessPauseSavingButShakeDoesNot() {
        XCTAssertTrue(FrameSweep.blocksCapture(.blurry))
        XCTAssertTrue(FrameSweep.blocksCapture(.tooDark))
        // A sweep is the slide moving, so shake is expected throughout.
        XCTAssertFalse(FrameSweep.blocksCapture(.shaky))
        XCTAssertFalse(FrameSweep.blocksCapture(nil))
    }

    func testAFrameIsNotKeptWhileTheImageIsBlurred() {
        let sweep = FrameSweep(thresholds: thresholds)

        for _ in 0..<10 {
            XCTAssertEqual(sweep.update(isSettled: true, issue: .blurry, shift: CGPoint(x: 50, y: 0)), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.prompt, .fixTheImage)
    }

    func testSavingResumesByItselfOnceTheBlurClears() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: .blurry, shift: CGPoint(x: 50, y: 0)), .wait)

        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 10, y: 0)), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testAFrameIsKeptWhileTheSlideKeepsMovingWithNoPromptToStop() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)

        // Shake all the way through: the slide is travelling, which is what a sweep is.
        XCTAssertEqual(sweep.update(isSettled: true, issue: .shaky, shift: CGPoint(x: 60, y: 0)), .wait)
        XCTAssertEqual(sweep.update(isSettled: true, issue: .shaky, shift: CGPoint(x: 60, y: 0)), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
        // Two frames fill the row, so the slide is sent down before the next one.
        XCTAssertEqual(sweep.prompt, .move(.down, kept: 2, of: 3))
    }

    func testTheSameFieldOfViewIsNotKeptTwice() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)

        // A still slide never travels the required distance, however many frames arrive.
        for _ in 0..<50 {
            XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 0)), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testWobbleBelowTheFloorDoesNotCountAsTravel() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)

        // 50 readings of 2 px would pass the 100 px mark if wobble were counted.
        for _ in 0..<50 {
            XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 2, y: 0)), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testTravelWhilePausedStillCounts() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)

        // Moved past a blurred patch: that ground should not have to be covered again.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: .blurry, shift: CGPoint(x: 120, y: 0)), .wait)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 0)), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testASlidePushedBackAndForthCoversNoNewGround() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)

        // 60 right, 60 back left: 120 pixels of movement, nothing new in view. Counting
        // distance alone would have kept a second frame of the same place.
        for _ in 0..<20 {
            XCTAssertEqual(
                sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 60, y: 0)), .wait)
            XCTAssertEqual(
                sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: -60, y: 0)), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testAFrameIsNotKeptMidLurch() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)

        // Far enough to want a frame, but moving too fast for the next one to line up on it.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 400, y: 0)), .wait)
        XCTAssertEqual(sweep.keptCount, 1)

        // Slowing down keeps it, and the ground already covered still counts.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 10, y: 0)), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testTheSlideIsWalkedAcrossInRows() {
        // Four frames to a row: right along the first, down a step, left along the second,
        // down again, then right along the third.
        let expected: [SweepDirection] = [
            .right, .right, .right, .right,
            .down, .left, .left, .left,
            .down, .right, .right, .right,
        ]
        for (kept, direction) in expected.enumerated() {
            XCTAssertEqual(
                FrameSweep.direction(afterKeeping: kept, framesPerRow: 4),
                direction,
                "after \(kept) frames"
            )
        }
    }

    func testThePromptFollowsThePath() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.prompt, .move(.right, kept: 0, of: 3))

        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: nil), .keepFrame)
        XCTAssertEqual(sweep.prompt, .move(.right, kept: 1, of: 3))

        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 120, y: 0)), .keepFrame)
        XCTAssertEqual(sweep.prompt, .move(.down, kept: 2, of: 3))
    }

    func testTheSweepEndsAfterTheFrameCount() {
        let sweep = FrameSweep(thresholds: thresholds)

        sweep.update(isSettled: true, issue: nil, shift: nil)
        sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 120, y: 0))
        sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 120, y: 0))

        XCTAssertEqual(sweep.keptCount, 3)
        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 3, stoppedEarly: false))
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 500, y: 0)), .wait)
    }

    func testTheSizeCeilingEndsTheSweepEarly() {
        let sweep = FrameSweep(thresholds: thresholds)
        sweep.update(isSettled: true, issue: nil, shift: nil)

        sweep.addWrittenBytes(1_200)

        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 1, stoppedEarly: true))
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 500, y: 0)), .wait)
    }

    func testResetStartsOver() {
        let sweep = FrameSweep(thresholds: thresholds)
        sweep.update(isSettled: true, issue: nil, shift: nil)
        sweep.addWrittenBytes(5_000)

        sweep.reset()

        XCTAssertFalse(sweep.isFinished)
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.bytesWritten, 0)
        XCTAssertEqual(sweep.prompt, .move(.right, kept: 0, of: 3))
    }

    func testTheSweepPatternNumbersTheFieldsTheWayTheSlideIsWalked() {
        let pattern = SweepPatternView()

        // First row runs left to right, the next comes back the other way, and so on, so
        // the slide is only ever nudged on from where it already is.
        XCTAssertEqual(pattern.position(of: 0).row, 0)
        XCTAssertEqual(pattern.position(of: 0).column, 0)
        XCTAssertEqual(pattern.position(of: 3).column, 3)
        XCTAssertEqual(pattern.position(of: 4).row, 1)
        XCTAssertEqual(pattern.position(of: 4).column, 3, "row two starts under the end of row one")
        XCTAssertEqual(pattern.position(of: 7).column, 0)
        XCTAssertEqual(pattern.position(of: 8).row, 2)
        XCTAssertEqual(pattern.position(of: 8).column, 0)
        XCTAssertEqual(pattern.position(of: 11).column, 3)
    }

    func testTheRowsOfASweepRunInAlternatingDirections() {
        let layout = SweepLayout(frameCount: 12)
        XCTAssertEqual(layout.indices(inRow: 0, frameCount: 12), [0, 1, 2, 3])
        XCTAssertEqual(layout.indices(inRow: 1, frameCount: 12), [7, 6, 5, 4])
        XCTAssertEqual(layout.indices(inRow: 2, frameCount: 12), [8, 9, 10, 11])
    }

    func testASweepThatStoppedEarlyStillGetsItsLastPartRow() {
        // Nine frames is two full rows and one on its own, not two rows with a frame lost.
        let layout = SweepLayout(frameCount: 9)
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.indices(inRow: 2, frameCount: 9), [8])
    }

}
