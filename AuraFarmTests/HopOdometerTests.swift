import XCTest

@testable import AuraFarm

final class HopOdometerTests: XCTestCase {
    /// Short side 100, so a hop is at 30 px and an offset is trusted up to 40 px.
    private let size = CGSize(width: 200, height: 100)

    func testHopsAccumulateWithSignsInBothAxes() {
        var odometer = HopOdometer()
        XCTAssertEqual(odometer.update(offset: CGPoint(x: 31, y: 0), frameSize: size).event, .hop)
        XCTAssertEqual(odometer.update(offset: CGPoint(x: 0, y: -32), frameSize: size).event, .hop)
        XCTAssertEqual(odometer.update(offset: CGPoint(x: -35, y: 0), frameSize: size).event, .hop)
        XCTAssertEqual(odometer.hops, 3)
        XCTAssertEqual(odometer.committed.x, -4, accuracy: 0.0001)
        XCTAssertEqual(odometer.committed.y, -32, accuracy: 0.0001)
        XCTAssertEqual(odometer.live, .zero)
    }

    func testReanchorsExactlyAtTheThreshold() {
        var odometer = HopOdometer()
        let below = odometer.update(offset: CGPoint(x: 29.9, y: 0), frameSize: size)
        XCTAssertEqual(below.event, .none)
        XCTAssertFalse(below.reanchor)
        XCTAssertEqual(odometer.position.x, 29.9, accuracy: 0.0001)

        let at = odometer.update(offset: CGPoint(x: 30, y: 0), frameSize: size)
        XCTAssertEqual(at.event, .hop)
        XCTAssertTrue(at.reanchor)
        XCTAssertEqual(odometer.position.x, 30, accuracy: 0.0001)
    }

    func testLiveOffsetCountsTowardPosition() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: CGPoint(x: 31, y: 0), frameSize: size)
        _ = odometer.update(offset: CGPoint(x: 10, y: 5), frameSize: size)
        XCTAssertEqual(odometer.position.x, 41, accuracy: 0.0001)
        XCTAssertEqual(odometer.position.y, 5, accuracy: 0.0001)
    }

    func testAnUntrustedLargeOffsetIsIgnored() {
        var odometer = HopOdometer()
        let result = odometer.update(offset: CGPoint(x: 41, y: 0), frameSize: size)
        XCTAssertEqual(result.event, .none)
        XCTAssertFalse(result.reanchor)
        XCTAssertEqual(odometer.position, .zero)
        XCTAssertEqual(odometer.hops, 0)
    }

    func testLostAfterReadingsToLoseNilsThenRegained() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: CGPoint(x: 10, y: 0), frameSize: size)
        XCTAssertEqual(odometer.update(offset: nil, frameSize: size).event, .none)
        XCTAssertEqual(odometer.update(offset: nil, frameSize: size).event, .none)
        let lost = odometer.update(offset: nil, frameSize: size)
        XCTAssertEqual(lost.event, .lost)
        XCTAssertTrue(lost.reanchor)
        XCTAssertTrue(odometer.isLost)
        XCTAssertEqual(odometer.gaps, 0)
        // The position holds where it was last known.
        XCTAssertEqual(odometer.position.x, 10, accuracy: 0.0001)
        // Lost is reported once, not on every further miss.
        XCTAssertEqual(odometer.update(offset: nil, frameSize: size).event, .none)

        let back = odometer.update(offset: CGPoint(x: 5, y: 0), frameSize: size)
        XCTAssertEqual(back.event, .regained)
        XCTAssertFalse(back.reanchor)
        XCTAssertFalse(odometer.isLost)
        XCTAssertEqual(odometer.gaps, 1)
    }

    func testATrustedOffsetClearsTheStreak() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: nil, frameSize: size)
        _ = odometer.update(offset: nil, frameSize: size)
        _ = odometer.update(offset: CGPoint(x: 1, y: 0), frameSize: size)
        XCTAssertEqual(odometer.update(offset: nil, frameSize: size).event, .none)
        XCTAssertFalse(odometer.isLost)
    }

    func testAHopWhileLostCountsAsRegained() {
        var odometer = HopOdometer()
        for _ in 0..<3 { _ = odometer.update(offset: nil, frameSize: size) }
        XCTAssertTrue(odometer.isLost)
        XCTAssertEqual(odometer.update(offset: CGPoint(x: 35, y: 0), frameSize: size).event, .hop)
        XCTAssertFalse(odometer.isLost)
        XCTAssertEqual(odometer.gaps, 1)
    }

    func testPositionInFrames() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: CGPoint(x: 30, y: 0), frameSize: size)
        _ = odometer.update(offset: CGPoint(x: 0, y: -20), frameSize: size)
        let frames = odometer.positionInFrames(shortSide: 100)
        XCTAssertEqual(frames.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(frames.y, -0.2, accuracy: 0.0001)
        XCTAssertEqual(odometer.positionInFrames(shortSide: 0), .zero)
    }

    func testReset() {
        var odometer = HopOdometer()
        _ = odometer.update(offset: CGPoint(x: 31, y: 0), frameSize: size)
        for _ in 0..<3 { _ = odometer.update(offset: nil, frameSize: size) }
        _ = odometer.update(offset: CGPoint(x: 5, y: 0), frameSize: size)
        odometer.reset()
        XCTAssertEqual(odometer.position, .zero)
        XCTAssertEqual(odometer.hops, 0)
        XCTAssertEqual(odometer.gaps, 0)
        XCTAssertFalse(odometer.isLost)
        // The streak was cleared too: two misses are not enough to be lost.
        _ = odometer.update(offset: nil, frameSize: size)
        XCTAssertEqual(odometer.update(offset: nil, frameSize: size).event, .none)
    }
}
