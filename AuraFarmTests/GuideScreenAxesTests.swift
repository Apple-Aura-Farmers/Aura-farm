import XCTest

@testable import AuraFarm

final class GuideScreenAxesTests: XCTestCase {
    func testEveryManualMappingRoundTripsThroughFromAndClosestMapping() {
        for mapping in ScreenMapping.allCases {
            for mirrored in [false, true] {
                let axes = GuideScreenAxes.from(mapping, mirrored: mirrored, pointsPerPixel: 0.6)
                let closest = axes.closestMapping()
                XCTAssertEqual(closest.mapping, mapping, "\(mapping) mirrored \(mirrored)")
                XCTAssertEqual(closest.mirrored, mirrored, "\(mapping) mirrored \(mirrored)")
                // Matches ScreenMapping.onScreen, scaled.
                let frame = CGPoint(x: 3, y: -2)
                let expected = mapping.onScreen(frame, mirrored: mirrored)
                let got = axes.screenVector(ofFrameVector: frame)
                XCTAssertEqual(Double(got.x), Double(expected.x) * 0.6, accuracy: 1e-9)
                XCTAssertEqual(Double(got.y), Double(expected.y) * 0.6, accuracy: 1e-9)
            }
        }
    }

    func testThreePointsRecoverARotationAndScale() throws {
        // The frame turned 90 degrees clockwise and shown at 0.4 points a pixel.
        let origin = CGPoint(x: 200, y: 300)
        let axes = try XCTUnwrap(
            GuideScreenAxes(
                origin: origin, xUnit: CGPoint(x: 200, y: 340), yUnit: CGPoint(x: 160, y: 300),
                framePixels: 100))
        XCTAssertEqual(axes.a, 0, accuracy: 1e-9)
        XCTAssertEqual(axes.c, 0.4, accuracy: 1e-9)
        XCTAssertEqual(axes.b, -0.4, accuracy: 1e-9)
        XCTAssertEqual(axes.d, 0, accuracy: 1e-9)
        let moved = axes.screenVector(ofFrameVector: CGPoint(x: 50, y: 0))
        XCTAssertEqual(Double(moved.x), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(moved.y), 20, accuracy: 1e-9)
        XCTAssertEqual(axes.closestMapping().mapping, .rotateRight)
        XCTAssertFalse(axes.closestMapping().mirrored)
    }

    func testTheInverseRoundTrips() throws {
        let axes = GuideScreenAxes(a: 0.3, b: -0.1, c: 0.2, d: 0.5)
        let frame = CGPoint(x: 12, y: -7)
        let back = try XCTUnwrap(axes.frameVector(ofScreenVector: axes.screenVector(ofFrameVector: frame)))
        XCTAssertEqual(Double(back.x), 12, accuracy: 1e-9)
        XCTAssertEqual(Double(back.y), -7, accuracy: 1e-9)
    }

    func testDegenerateInputGivesNil() {
        let origin = CGPoint(x: 10, y: 10)
        XCTAssertNil(
            GuideScreenAxes(
                origin: origin, xUnit: CGPoint(x: 20, y: 10), yUnit: CGPoint(x: 30, y: 10),
                framePixels: 100))
        XCTAssertNil(
            GuideScreenAxes(origin: origin, xUnit: origin, yUnit: origin, framePixels: 100))
        XCTAssertNil(
            GuideScreenAxes(
                origin: origin, xUnit: CGPoint(x: 20, y: 10), yUnit: CGPoint(x: 10, y: 20),
                framePixels: 0))
        XCTAssertNil(GuideScreenAxes(a: 1, b: 2, c: 2, d: 4).frameVector(ofScreenVector: .zero))
    }

    func testASpotAheadOfTheViewLandsOnThatSideOfTheCentre() {
        // The view travels to the right in the frame, and the frame is shown rotated left: a
        // spot ahead (frame +x) must show on the side the view's travel points to on screen.
        let axes = GuideScreenAxes.from(.rotateLeft, mirrored: false, pointsPerPixel: 1)
        let centre = CGPoint(x: 100, y: 100)
        let ahead = axes.screenVector(ofFrameVector: CGPoint(x: 50, y: 0))
        XCTAssertEqual(Double(centre.x + ahead.x), 100, accuracy: 1e-9)
        XCTAssertLessThan(centre.y + ahead.y, 100, "rotate left sends frame +x up the screen")
        let plain = GuideScreenAxes.from(.asIs, mirrored: false, pointsPerPixel: 1)
        XCTAssertGreaterThan(centre.x + plain.screenVector(ofFrameVector: CGPoint(x: 50, y: 0)).x, 100)
    }
}
