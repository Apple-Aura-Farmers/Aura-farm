import XCTest

@testable import AuraFarm

/// Phase 2n part B: a frame whose frame-to-frame shift is too large to be real (the +-242 px
/// ghosts of 16 Nov 2026) is dropped, and everything carries on from the last good frame.
final class GhostFrameTests: XCTestCase {
    private let size = 256
    private lazy var texture = SyntheticFrame.smoothNoise(size: size)
    private lazy var frameSize = CGSize(width: size, height: size)
    private lazy var box = EyepieceField.centreSquare(frameSize: frameSize)  // 179 px: 0.4 is 71
    private var seconds = 0.0
    private var indicators = MovementIndicators()

    private func still() -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { [size, texture] x, y in
            UInt8(texture[y * size + x])
        }
    }

    private func track(_ tracker: SlideTracker) -> SlideTrackerReading {
        seconds += 0.1
        let reading = tracker.track(still(), box: box, frameSize: frameSize, seconds: seconds)
        indicators.update(
            shake: reading.frameShift, anchorOffset: reading.usedOffset,
            positionFields: reading.positionFields, isLost: reading.isLost, event: reading.event,
            referenceSide: reading.boxSide, seconds: seconds, hopDistance: reading.hopLimit,
            hasDetail: reading.hasDetail)
        return reading
    }

    func testAStillSequenceWithAPlusAndMinusGhostPairDropsThemAndStaysCalm() {
        let tracker = SlideTracker()
        // The registration says +242 on frame 6 (the ghost, against frame 5); frame 7 is then
        // measured against frame 5 again, the last good one, and reads 0.
        tracker.frameShiftOverride = { index, measured in
            index == 6 ? CGPoint(x: 242, y: 0) : measured
        }
        var readings: [SlideTrackerReading] = []
        var speeds: [Double] = []
        for _ in 0..<12 {
            readings.append(track(tracker))
            speeds.append(indicators.speedFraction)
            XCTAssertNotEqual(indicators.status, .tooFast)
        }
        XCTAssertEqual(readings[5].reading, "ghost")
        XCTAssertEqual(readings.last?.ghostFrames, 1)
        XCTAssertEqual(readings.last?.position, readings[4].position, "position unchanged")
        XCTAssertLessThan(speeds.max() ?? 1, indicators.thresholds.comfortableSpeedFraction)
        // The ghost frame carries the last good shake, so speed and stillness go on.
        XCTAssertEqual(readings[5].frameShift, readings[4].frameShift)
        XCTAssertGreaterThan(indicators.stillSeconds, 0.5)
        XCTAssertNotEqual(readings[6].reading, "ghost")
    }

    func testARealMoveOfThirtyPixelsAFrameIsNotAGhost() {
        let tracker = SlideTracker()
        tracker.frameShiftOverride = { _, _ in CGPoint(x: 30, y: 0) }
        tracker.anchorReadingOverride = { index, _ in CGPoint(x: 30 * Double(index), y: 0) }
        var last = track(tracker)
        for _ in 0..<5 { last = track(tracker) }
        XCTAssertEqual(last.ghostFrames, 0)
        XCTAssertNotEqual(last.reading, "ghost")
        XCTAssertGreaterThan(last.position.x, 100)
    }

    func testThreeGhostsInARowFallBackToTheMissingShiftRule() {
        let tracker = SlideTracker()
        tracker.frameShiftOverride = { index, measured in
            (6...8).contains(index) ? CGPoint(x: 242, y: 0) : measured
        }
        tracker.anchorReadingOverride = { _, _ in .zero }
        var readings: [SlideTrackerReading] = []
        for _ in 0..<11 { readings.append(track(tracker)) }
        XCTAssertEqual(readings[5].reading, "ghost")
        XCTAssertEqual(readings[6].reading, "ghost")
        // The third in a row is let through with no shift: the anchor stands, the chain is broken.
        XCTAssertNotEqual(readings[7].reading, "ghost")
        XCTAssertEqual(readings[7].reading, "measured")
        XCTAssertNil(readings[7].chain)
        XCTAssertEqual(readings[7].ghostFrames, 3)
        XCTAssertEqual(readings[7].ghostFallbacks, 1)
        // And the previous frame moved on: the next frame is judged normally.
        XCTAssertNotEqual(readings[8].reading, "ghost")
        XCTAssertEqual(readings.last?.ghostFrames, 3)
    }
}
