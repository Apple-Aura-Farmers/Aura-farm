import XCTest

@testable import MicroscopeCounter

final class FrameSweepTests: XCTestCase {
    private let thresholds = SweepThresholds(
        framesPerSweep: 3,
        shiftBetweenFrames: 100,
        ignoreShiftBelow: 3,
        maxBytes: 1_000
    )

    func testTheFirstFrameIsKeptAsSoonAsTheImageIsGood() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: nil), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testNothingIsKeptUntilTheCheckHasSettled() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isSettled: false, issue: nil, shakePixels: nil), .wait)
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
            XCTAssertEqual(sweep.update(isSettled: true, issue: .blurry, shakePixels: 50), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.prompt, .fixTheImage)
    }

    func testSavingResumesByItselfOnceTheBlurClears() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: .blurry, shakePixels: 50), .wait)

        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: 10), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testAFrameIsKeptWhileTheSlideKeepsMovingWithNoPromptToStop() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: nil), .keepFrame)

        // Shake all the way through: the slide is travelling, which is what a sweep is.
        XCTAssertEqual(sweep.update(isSettled: true, issue: .shaky, shakePixels: 60), .wait)
        XCTAssertEqual(sweep.update(isSettled: true, issue: .shaky, shakePixels: 60), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
        XCTAssertEqual(sweep.prompt, .moveLeft(kept: 2, of: 3))
    }

    func testTheSameFieldOfViewIsNotKeptTwice() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: nil), .keepFrame)

        // A still slide never travels the required distance, however many frames arrive.
        for _ in 0..<50 {
            XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: 0), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testWobbleBelowTheFloorDoesNotCountAsTravel() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: nil), .keepFrame)

        // 50 readings of 2 px would pass the 100 px mark if wobble were counted.
        for _ in 0..<50 {
            XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: 2), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testTravelWhilePausedStillCounts() {
        let sweep = FrameSweep(thresholds: thresholds)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: nil), .keepFrame)

        // Moved past a blurred patch: that ground should not have to be covered again.
        XCTAssertEqual(sweep.update(isSettled: true, issue: .blurry, shakePixels: 120), .wait)
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: 0), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testTheSweepEndsAfterTheFrameCount() {
        let sweep = FrameSweep(thresholds: thresholds)

        sweep.update(isSettled: true, issue: nil, shakePixels: nil)
        sweep.update(isSettled: true, issue: nil, shakePixels: 120)
        sweep.update(isSettled: true, issue: nil, shakePixels: 120)

        XCTAssertEqual(sweep.keptCount, 3)
        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 3, stoppedEarly: false))
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: 500), .wait)
    }

    func testTheSizeCeilingEndsTheSweepEarly() {
        let sweep = FrameSweep(thresholds: thresholds)
        sweep.update(isSettled: true, issue: nil, shakePixels: nil)

        sweep.addWrittenBytes(1_200)

        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 1, stoppedEarly: true))
        XCTAssertEqual(sweep.update(isSettled: true, issue: nil, shakePixels: 500), .wait)
    }

    func testResetStartsOver() {
        let sweep = FrameSweep(thresholds: thresholds)
        sweep.update(isSettled: true, issue: nil, shakePixels: nil)
        sweep.addWrittenBytes(5_000)

        sweep.reset()

        XCTAssertFalse(sweep.isFinished)
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.bytesWritten, 0)
        XCTAssertEqual(sweep.prompt, .moveLeft(kept: 0, of: 3))
    }
}
