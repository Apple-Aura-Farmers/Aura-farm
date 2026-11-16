import XCTest

@testable import AuraFarm

/// Phase 2l part B: the four quarters in heading terms.
final class BoxQuartersTests: XCTestCase {
    private let halves = BoxHalves(
        left: 0, right: 0, top: 0, bottom: 0, topLeft: 1, topRight: 2, bottomLeft: 3, bottomRight: 4)

    func testAheadAndBehindTowardAndAwayFromTheLowSide() throws {
        // Travelling up in the frame (ahead is the top), the low side half is the left one.
        let up = try XCTUnwrap(
            halves.quarters(forFrameDirection: CGPoint(x: 0, y: -1), lowSide: .left))
        XCTAssertEqual(up.aheadToward, 1)
        XCTAssertEqual(up.aheadAway, 2)
        XCTAssertEqual(up.behindToward, 3)
        XCTAssertEqual(up.behindAway, 4)
        // The low side on the right instead: toward and away swap.
        let right = try XCTUnwrap(
            halves.quarters(forFrameDirection: CGPoint(x: 0, y: -1), lowSide: .right))
        XCTAssertEqual(right.aheadToward, 2)
        XCTAssertEqual(right.behindAway, 3)
        // Travelling right (ahead is the right half), low side on top.
        let across = try XCTUnwrap(
            halves.quarters(forFrameDirection: CGPoint(x: 1, y: 0), lowSide: .top))
        XCTAssertEqual(across.aheadToward, 2)
        XCTAssertEqual(across.aheadAway, 4)
        XCTAssertEqual(across.behindToward, 1)
        XCTAssertEqual(across.behindAway, 3)
        XCTAssertNil(halves.quarters(forFrameDirection: .zero, lowSide: .left))
    }

    func testTheTrackerMeasuresTheQuartersAndReportsTheCost() {
        let size = CGSize(width: 1280, height: 720)
        let box = CGRect(x: 465, y: 185, width: 358, height: 358)
        let noise = SyntheticFrame.noise(width: 1280, height: 720)
        let buffer = SyntheticFrame.make(width: 1280, height: 720) { x, y in
            noise[y * 1280 + x]
        }
        let tracker = SlideTracker()
        let reading = tracker.track(buffer, box: box, frameSize: size, seconds: 0)
        let halves = reading.halfSharpness
        XCTAssertGreaterThan(halves?.topLeft ?? 0, 0)
        XCTAssertGreaterThan(halves?.bottomRight ?? 0, 0)
        print("quarter ms per frame (simulator debug): \(tracker.quarterMilliseconds)")
    }
}
