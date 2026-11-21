import XCTest

@testable import AuraFarm

final class StageMotionPlannerTests: XCTestCase {
    private func planner(swapped: Bool = false, chunk: Int = 3) -> StageMotionPlanner {
        let x = swapped ? CGPoint(x: 0, y: 0.2) : CGPoint(x: 0.2, y: 0)
        let y = swapped ? CGPoint(x: 0.2, y: 0) : CGPoint(x: 0, y: 0.2)
        let axes = StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!
        return StageMotionPlanner(
            mapping: StageServoMapping(x: x, y: y, swapped: swapped, axes: axes), chunkDegrees: chunk)
    }

    func testIdle() {
        XCTAssertEqual(planner().next(angles: (90, 90), target: nil), .idle)
        XCTAssertEqual(planner().next(angles: (90, 90), target: CGPoint(x: 0.05, y: 0.05)), .idle)
    }

    func testPicksLargerServo() {
        XCTAssertEqual(
            planner().next(angles: (90, 90), target: CGPoint(x: 0.2, y: 1.0)),
            .move(servo: .y, toAngle: 93))
        XCTAssertEqual(
            planner().next(angles: (90, 90), target: CGPoint(x: -1.0, y: 0.2)),
            .move(servo: .x, toAngle: 87))
    }

    func testChunkClamp() {
        XCTAssertEqual(
            planner(chunk: 5).next(angles: (90, 90), target: CGPoint(x: 20, y: 0)),
            .move(servo: .x, toAngle: 95))
    }

    func testSubDegreeSteps() {
        // 0.2 fields = 1 degree.
        var p = planner()
        p.deadbandFields = 0.01
        XCTAssertEqual(p.next(angles: (90, 90), target: CGPoint(x: 0.06, y: 0)), .idle)
        XCTAssertEqual(
            p.next(angles: (90, 90), target: CGPoint(x: 0.12, y: 0)), .move(servo: .x, toAngle: 91))
        XCTAssertEqual(
            p.next(angles: (90, 90), target: CGPoint(x: -0.12, y: 0)), .move(servo: .x, toAngle: 89))
    }

    func testAngleClamp() {
        XCTAssertEqual(
            planner().next(angles: (179, 90), target: CGPoint(x: 20, y: 0)),
            .move(servo: .x, toAngle: 180))
    }

    func testAtLimit() {
        XCTAssertEqual(
            planner().next(angles: (0, 90), target: CGPoint(x: -1, y: 0)), .atLimit(.x))
        XCTAssertEqual(
            planner().next(angles: (90, 180), target: CGPoint(x: 0, y: 1)), .atLimit(.y))
        // Away from the limit it still moves.
        XCTAssertEqual(
            planner().next(angles: (0, 90), target: CGPoint(x: 1, y: 0)),
            .move(servo: .x, toAngle: 3))
    }

    func testSwappedMapping() {
        // Picture must move +x: with swapped servos that is the Y servo.
        XCTAssertEqual(
            planner(swapped: true).next(angles: (90, 90), target: CGPoint(x: 1, y: 0.1)),
            .move(servo: .y, toAngle: 93))
    }

    func testFreeServoUsedWhenDominantIsPinned() {
        // X wants +10 degrees (2 fields) but is at 180; Y needs 5 degrees (1 field).
        XCTAssertEqual(
            planner().next(angles: (180, 90), target: CGPoint(x: 2, y: 1)),
            .move(servo: .y, toAngle: 93))
    }

    func testBothPinnedIsAtLimit() {
        XCTAssertEqual(
            planner().next(angles: (180, 180), target: CGPoint(x: 2, y: 1)), .atLimit(.x))
        // The other servo needs under a degree: nothing to move, so still at limit.
        XCTAssertEqual(
            planner().next(angles: (180, 90), target: CGPoint(x: 2, y: 0.05)), .atLimit(.x))
    }
}
