import XCTest

@testable import AuraFarm

final class FieldCircleTests: XCTestCase {
    private let frame = CGSize(width: 320, height: 240)

    func testACircleBecomesAMaskAndBackAgain() throws {
        let circle = FieldCircle(centre: CGPoint(x: 150, y: 120), radius: 90)
        let mask = circle.mask(frameSize: frame)
        XCTAssertTrue(mask.eyepiece[0], "the corner is ring")
        XCTAssertFalse(mask.eyepiece[15 * 40 + 19], "the middle is open")
        XCTAssertTrue(mask.isTrusted)
        let fitted = try XCTUnwrap(FieldCircle(fitting: mask))
        XCTAssertEqual(fitted.centre.x, 150, accuracy: 6)
        XCTAssertEqual(fitted.centre.y, 120, accuracy: 6)
        XCTAssertEqual(fitted.radius, 90, accuracy: 6)
    }

    func testTheRegistrationSquareIsInsideTheCircleAndWholePixels() throws {
        let circle = FieldCircle(centre: CGPoint(x: 150, y: 120), radius: 90)
        let rect = try XCTUnwrap(circle.mask(frameSize: frame).registrationRect)
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY),
        ] {
            XCTAssertLessThan(hypot(corner.x - 150, corner.y - 120), 90)
        }
        for value in [rect.minX, rect.minY, rect.width, rect.height] {
            XCTAssertEqual(value, value.rounded())
        }
    }

    func testACircleRunningOffTheFrameStaysInsideIt() throws {
        let circle = FieldCircle(centre: CGPoint(x: 20, y: 20), radius: 150)
        let rect = try XCTUnwrap(circle.mask(frameSize: frame).registrationRect)
        XCTAssertTrue(CGRect(origin: .zero, size: frame).contains(rect))
    }

    func testClampingKeepsTheRadiusAndCentreSensible() {
        let tiny = FieldCircle(centre: CGPoint(x: -50, y: 500), radius: 1).clamped(to: frame)
        XCTAssertEqual(tiny.radius, 24, accuracy: 0.0001)
        XCTAssertEqual(tiny.centre, CGPoint(x: 0, y: 240))
        let huge = FieldCircle(centre: CGPoint(x: 100, y: 100), radius: 900).clamped(to: frame)
        XCTAssertEqual(huge.radius, 192, accuracy: 0.0001)
    }

    func testNothingOpenCannotBeFitted() {
        let mask = FieldMask(
            gridWidth: 2, gridHeight: 2, gridStep: 8, eyepiece: [true, true, true, true],
            openShare: 0, registrationRect: nil)
        XCTAssertNil(FieldCircle(fitting: mask))
    }
}
