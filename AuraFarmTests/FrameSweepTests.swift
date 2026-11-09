import CoreGraphics
import XCTest

@testable import AuraFarm

final class FrameSweepTests: XCTestCase {
    private let thresholds = SweepThresholds(
        framesPerSweep: 3,
        framesPerRow: 2,
        shiftBetweenFrames: 100,
        shiftBetweenRows: 500,
        maxStepPixels: 150,
        maxBytes: 1_000
    )

    func testTheFirstFrameIsKeptAsSoonAsTheImageIsGood() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testNothingIsKeptUntilTheCheckHasSettled() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isSettled: false, issue: nil, shift: nil, travel: nil), .wait)
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
            XCTAssertEqual(
                sweep.update(
                    isSettled: true, issue: .blurry, shift: CGPoint(x: 50, y: 0), travel: 50),
                .wait)
        }
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.prompt, .fixTheImage)
    }

    func testSavingResumesByItselfOnceTheBlurClears() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: .blurry, shift: CGPoint(x: 50, y: 0), travel: nil),
            .wait)

        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 10, y: 0), travel: nil),
            .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testAFrameIsKeptWhileTheSlideKeepsMovingWithNoPromptToStop() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // Shake all the way through: the slide is travelling, which is what a sweep is.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: .shaky, shift: CGPoint(x: 60, y: 0), travel: 60),
            .wait)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: .shaky, shift: CGPoint(x: 60, y: 0), travel: 120),
            .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
        // Two frames fill the row, so the slide is sent down before the next one.
        XCTAssertEqual(sweep.prompt, .move(.down, kept: 2, of: 3))
    }

    func testTheSameFieldOfViewIsNotKeptTwice() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // A still slide never travels the required distance, however many frames arrive.
        for _ in 0..<50 {
            XCTAssertEqual(
                sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 0), travel: 0),
                .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testTravelIsMeasuredFromTheLastKeptFrameRatherThanFrameToFrame() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // Big frame-to-frame readings with the view back where it started: a running total
        // would have passed 100 px long ago, but no new ground has been covered.
        for _ in 0..<20 {
            XCTAssertEqual(
                sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 60, y: 0), travel: 60),
                .wait)
            XCTAssertEqual(
                sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: -60, y: 0), travel: 0),
                .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testTravelWhilePausedStillCounts() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // Moved past a blurred patch: that ground should not have to be covered again.
        XCTAssertEqual(
            sweep.update(
                isSettled: true, issue: .blurry, shift: CGPoint(x: 120, y: 0), travel: 120),
            .wait)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 0), travel: 120),
            .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testAFrameIsNotKeptMidLurch() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // Far enough to want a frame, but moving too fast for the next one to line up on it.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 300, y: 0), travel: 300),
            .wait)
        XCTAssertEqual(sweep.keptCount, 1)

        // Slowing down keeps it, and the ground already covered still counts.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 10, y: 0), travel: 310),
            .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testAFrameIsKeptWhenThereIsNoLongerAnythingToMeasureAgainst() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // No reading at all: the view and the last kept frame have nothing in common any
        // more. Waiting for the distance to reach the mark would be waiting for a reading
        // that cannot come back, so this frame starts a fresh run.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 20, y: 0), travel: nil),
            .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testAFrameWithNothingToMeasureAgainstStillHasToBeWorthKeeping() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)

        // Out of reach of the last kept frame and blurred: starting a fresh run on a frame
        // the next ones could not line up against would gain nothing.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: .blurry, shift: nil, travel: nil), .wait)
        XCTAssertEqual(sweep.keptCount, 1)
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

        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)
        XCTAssertEqual(sweep.prompt, .move(.right, kept: 1, of: 3))

        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 120, y: 0), travel: 120),
            .keepFrame)
        XCTAssertEqual(sweep.prompt, .move(.down, kept: 2, of: 3))
    }

    func testTheSweepEndsAfterTheFrameCount() {
        let sweep = FrameSweep(thresholds: thresholds)

        sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil)
        sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 120, y: 0), travel: 120)
        // Two frames fill a row here, so the third is the step down and wants a row's worth.
        sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 120), travel: 500)

        XCTAssertEqual(sweep.keptCount, 3)
        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 3, stoppedEarly: false))
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 500, y: 0), travel: 500),
            .wait)
    }

    func testTheSizeCeilingEndsTheSweepEarly() {
        let sweep = FrameSweep(thresholds: thresholds)
        sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil)

        sweep.addWrittenBytes(1_200)

        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 1, stoppedEarly: true))
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 500, y: 0), travel: 500),
            .wait)
    }

    func testResetStartsOver() {
        let sweep = FrameSweep(thresholds: thresholds)
        sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil)
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

    func testTheStepDownBetweenRowsWaitsForAWholeRow() {
        // Two frames fill a row in these thresholds, so the third starts a new one.
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: nil, travel: nil), .keepFrame)
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 10, y: 0), travel: 120),
            .keepFrame)
        XCTAssertEqual(sweep.prompt, .move(.down, kept: 2, of: 3))

        // A sideways nudge's worth of travel is not a row, so nothing is kept yet and the
        // helper is still being told to go down.
        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 10), travel: 120),
            .wait)
        XCTAssertEqual(sweep.keptCount, 2)
        XCTAssertEqual(sweep.prompt, .move(.down, kept: 2, of: 3))

        XCTAssertEqual(
            sweep.update(isSettled: true, issue: nil, shift: CGPoint(x: 0, y: 10), travel: 500),
            .keepFrame)
        XCTAssertEqual(sweep.keptCount, 3)
    }

    func testTheGuideBarFillsTheWayTheSlideIsBeingPushed() {
        // Row one runs left to right and row two comes back, so the bar has to run back too
        // or it would fill against the direction of the arrow on it.
        XCTAssertEqual(SweepGuide.cells(inRow: 1, framesPerRow: 4), [0, 1, 2, 3])
        XCTAssertEqual(SweepGuide.cells(inRow: 2, framesPerRow: 4), [3, 2, 1, 0])
        XCTAssertEqual(SweepGuide.cells(inRow: 3, framesPerRow: 4), [0, 1, 2, 3])
    }

    func testASweepThatStoppedEarlyStillGetsItsLastPartRow() {
        // Nine frames is two full rows and one on its own, not two rows with a frame lost.
        let layout = SweepLayout(frameCount: 9)
        XCTAssertEqual(layout.rows, 3)
        XCTAssertEqual(layout.indices(inRow: 2, frameCount: 9), [8])
    }

}
