import XCTest

@testable import AuraFarm

final class BoxHalvesTests: XCTestCase {
    func testAheadIsTheSideTheViewTravelsToward() {
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: 1, y: 0)), .right)
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: -1, y: 0)), .left)
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: 0, y: 1)), .bottom)
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: 0, y: -1)), .top)
    }

    func testADiagonalPicksTheDominantAxis() {
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: -0.8, y: 0.5)), .left)
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: 0.4, y: -0.9)), .top)
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: 0.6, y: 0.7)), .bottom)
        XCTAssertEqual(BoxHalves.ahead(forFrameDirection: CGPoint(x: 0.5, y: 0.5)), .right, "x on a tie")
        XCTAssertNil(BoxHalves.ahead(forFrameDirection: .zero))
    }

    func testAheadAndBehindAreOppositeHalves() throws {
        let halves = BoxHalves(left: 10, right: 20, top: 30, bottom: 40)
        let leftward = try XCTUnwrap(halves.aheadAndBehind(forFrameDirection: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(leftward.ahead, 10)
        XCTAssertEqual(leftward.behind, 20)
        let downward = try XCTUnwrap(halves.aheadAndBehind(forFrameDirection: CGPoint(x: 0, y: 1)))
        XCTAssertEqual(downward.ahead, 40)
        XCTAssertEqual(downward.behind, 30)
        XCTAssertNil(halves.aheadAndBehind(forFrameDirection: .zero))
    }

    func testFocusRatiosFollowTheSameAheadAndBehindChoice() throws {
        let ratios = HalfFocus(left: 0.2, right: 0.9, top: nil, bottom: 1.1)
        let leftward = try XCTUnwrap(ratios.aheadAndBehind(forFrameDirection: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(try XCTUnwrap(leftward.ahead), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(leftward.behind), 0.9, accuracy: 1e-9)
        let upward = try XCTUnwrap(ratios.aheadAndBehind(forFrameDirection: CGPoint(x: 0, y: -1)))
        XCTAssertNil(upward.ahead)
        XCTAssertEqual(try XCTUnwrap(upward.behind), 1.1, accuracy: 1e-9)
        XCTAssertNil(ratios.aheadAndBehind(forFrameDirection: .zero))
    }

    func testTheTrackerMeasuresEachHalfAtTheStatsStep() throws {
        // Texture in the left half of the box only.
        let size = 256
        let texture = SyntheticFrame.smoothNoise(size: size)
        let buffer = SyntheticFrame.make(width: size, height: size) { x, y in
            x < 128 ? UInt8(texture[y * size + x]) : 90
        }
        let frame = CGSize(width: size, height: size)
        let box = EyepieceField.centreSquare(frameSize: frame)
        let reading = SlideTracker().track(buffer, box: box, frameSize: frame, seconds: 0)
        let halves = try XCTUnwrap(reading.halfSharpness)
        XCTAssertGreaterThan(halves.left, 120)
        XCTAssertLessThan(halves.right, 1)
        XCTAssertGreaterThan(halves.top, 0, "both halves of a split box see some of the texture")
        XCTAssertNil(SlideTracker().idle(buffer, box: box, frameSize: frame).halfSharpness)
        XCTAssertNil(
            SlideTracker().track(buffer, box: nil, frameSize: frame, seconds: 0).halfSharpness)
    }

    func testThePreviewAxesAreComparedWithThePickerThroughTheViewTravelMap() {
        // The preview shows the frame's x to the right of the screen's rotation "right"; the
        // content then moves that way and the view the opposite way: "Rotate 90° left".
        let preview = GuideScreenAxes.from(.rotateRight, mirrored: false, pointsPerPixel: 0.5)
        XCTAssertEqual(preview.viewTravel.closestMapping().mapping, .rotateLeft)
        XCTAssertFalse(preview.viewTravel.closestMapping().mirrored)
        XCTAssertEqual(preview.viewTravel.viewTravel, preview)
    }
}
