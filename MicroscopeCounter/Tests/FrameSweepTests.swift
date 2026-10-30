import XCTest

@testable import MicroscopeCounter

final class FrameSweepTests: XCTestCase {
    private let thresholds = SweepThresholds(
        framesPerSweep: 3,
        movingShakePixels: 8,
        stillReadingsBeforeCapture: 2,
        maxBytes: 1_000
    )

    func testFirstFrameIsKeptOnlyAfterTheImageHoldsStill() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .wait)
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testNothingIsKeptWhileTheImageIsBad() {
        let sweep = FrameSweep(thresholds: thresholds)

        for _ in 0..<10 {
            XCTAssertEqual(sweep.update(isImageGood: false, shakePixels: 0), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.prompt, .fixTheImage)
    }

    func testAStillStreakIsBrokenByShake() {
        let sweep = FrameSweep(thresholds: thresholds)

        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .wait)
        // Over the moving threshold, so the streak restarts.
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 20), .wait)
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .wait)
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .keepFrame)
    }

    func testAfterAFrameItAsksToMoveLeftAndWaitsForTheMove() {
        let sweep = FrameSweep(thresholds: thresholds)
        keepOneFrame(with: sweep)

        XCTAssertEqual(sweep.prompt, .moveLeft(kept: 1, of: 3))
        // Still frames while it waits for the move must not be kept, however many arrive.
        for _ in 0..<10 {
            XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 0), .wait)
        }
        XCTAssertEqual(sweep.keptCount, 1)
    }

    func testTheNextFrameIsKeptAfterAMoveThenStillness() {
        let sweep = FrameSweep(thresholds: thresholds)
        keepOneFrame(with: sweep)

        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 30), .wait)
        XCTAssertEqual(sweep.prompt, .holdStill(kept: 1, of: 3))
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .wait)
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 1), .keepFrame)
        XCTAssertEqual(sweep.keptCount, 2)
    }

    func testTheSweepEndsAfterTheFrameCount() {
        let sweep = FrameSweep(thresholds: thresholds)

        keepOneFrame(with: sweep)
        moveAndKeepOneFrame(with: sweep)
        moveAndKeepOneFrame(with: sweep)

        XCTAssertEqual(sweep.keptCount, 3)
        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 3, stoppedEarly: false))
        // A finished sweep keeps nothing more.
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 0), .wait)
    }

    func testTheSizeCeilingEndsTheSweepEarly() {
        let sweep = FrameSweep(thresholds: thresholds)
        keepOneFrame(with: sweep)

        sweep.addWrittenBytes(1_200)

        XCTAssertTrue(sweep.isFinished)
        XCTAssertEqual(sweep.prompt, .done(kept: 1, stoppedEarly: true))
        XCTAssertEqual(sweep.update(isImageGood: true, shakePixels: 0), .wait)
    }

    func testResetStartsOver() {
        let sweep = FrameSweep(thresholds: thresholds)
        keepOneFrame(with: sweep)
        sweep.addWrittenBytes(5_000)

        sweep.reset()

        XCTAssertFalse(sweep.isFinished)
        XCTAssertEqual(sweep.keptCount, 0)
        XCTAssertEqual(sweep.bytesWritten, 0)
        XCTAssertEqual(sweep.prompt, .holdStill(kept: 0, of: 3))
    }

    // MARK: Helpers

    private func keepOneFrame(with sweep: FrameSweep) {
        for _ in 0..<thresholds.stillReadingsBeforeCapture {
            sweep.update(isImageGood: true, shakePixels: 1)
        }
    }

    private func moveAndKeepOneFrame(with sweep: FrameSweep) {
        sweep.update(isImageGood: true, shakePixels: thresholds.movingShakePixels + 10)
        keepOneFrame(with: sweep)
    }
}
