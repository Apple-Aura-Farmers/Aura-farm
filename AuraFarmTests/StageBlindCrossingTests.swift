import XCTest

@testable import AuraFarm

final class StageBlindCrossingTests: XCTestCase {
    private let mapping: StageServoMapping = {
        let axes = StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!
        return StageServoMapping(
            x: CGPoint(x: 0.1, y: 0.02), y: CGPoint(x: 0, y: 0.2), swapped: false, axes: axes)
    }()

    func testMovedFieldsFromAngleChanges() {
        let c = StageBlindCrossing(direction: CGPoint(x: 1, y: 0), startAngles: (90, 90))
        let moved = c.movedFields(angles: (100, 95), mapping: mapping)
        XCTAssertEqual(moved.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(moved.y, 0.2 + 1.0, accuracy: 1e-9)
        let back = c.movedFields(angles: (90, 90), mapping: mapping)
        XCTAssertEqual(back, .zero)
    }

    func testReachedCapAtAndBelow() {
        let c = StageBlindCrossing(
            direction: CGPoint(x: 1, y: 0), startAngles: (90, 90), capFields: 1.0)
        XCTAssertFalse(c.reachedCap(angles: (99, 90), mapping: mapping))
        // 10 degrees of X: (1.0, 0.2) is longer than 1 field.
        XCTAssertTrue(c.reachedCap(angles: (100, 90), mapping: mapping))
        let exact = StageBlindCrossing(
            direction: CGPoint(x: 0, y: 1), startAngles: (90, 90), capFields: 1.0)
        XCTAssertTrue(exact.reachedCap(angles: (90, 95), mapping: mapping))
        XCTAssertFalse(exact.reachedCap(angles: (90, 94), mapping: mapping))
    }

    func testExtendCap() {
        var c = StageBlindCrossing(direction: CGPoint(x: 1, y: 0), startAngles: (90, 90))
        XCTAssertEqual(c.capFields, 2.0)
        c.extendCap()
        XCTAssertEqual(c.capFields, 4.0)
        c.extendCap(by: 0.5)
        XCTAssertEqual(c.capFields, 4.5)
    }

    func testTargetIsUnit() {
        let c = StageBlindCrossing(direction: CGPoint(x: 3, y: 4), startAngles: (90, 90))
        XCTAssertEqual(c.target().x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(c.target().y, 0.8, accuracy: 1e-9)
        XCTAssertEqual(
            StageBlindCrossing(direction: .zero, startAngles: (0, 0)).target(), .zero)
    }
}
