import XCTest

@testable import AuraFarm

final class StageHandReturnTests: XCTestCase {
    /// Walks the plan from `start` as the board would; returns the moves in order.
    private func walk(
        _ plan: StageHandReturn, from start: (x: Int, y: Int)
    ) -> [(servo: StageAxis, angle: Int)] {
        var plan = plan
        var angles = start
        var moves: [(servo: StageAxis, angle: Int)] = []
        for _ in 0..<200 {
            guard let next = plan.nextStep(angles: angles) else { return moves }
            moves.append(next)
            if next.servo == .x { angles.x = next.angle } else { angles.y = next.angle }
        }
        XCTFail("did not finish")
        return moves
    }

    private func plan(
        saved: (x: Int, y: Int) = (90, 90), chunk: Int = 3, limits: StageLimits = StageLimits(),
        moved: (x: Bool, y: Bool) = (true, true), direction: (x: Int, y: Int) = (0, 0)
    ) -> StageHandReturn {
        StageHandReturn(
            saved: saved, chunk: chunk, limits: limits, moved: moved, direction: direction)
    }

    func testYComesFirstThenX() {
        let moves = walk(plan(), from: (100, 80))
        XCTAssertEqual(moves.first?.servo, .y)
        let firstX = moves.firstIndex { $0.servo == .x }
        XCTAssertNotNil(firstX)
        XCTAssertTrue(moves[..<firstX!].allSatisfy { $0.servo == .y })
        XCTAssertTrue(moves[firstX!...].allSatisfy { $0.servo == .x })
        XCTAssertEqual(moves.last?.servo, .x)
        XCTAssertEqual(moves.last?.angle, 90)
    }

    func testOnlyServosThatMovedAreTouched() {
        let moves = walk(plan(moved: (x: false, y: true)), from: (100, 80))
        XCTAssertTrue(moves.allSatisfy { $0.servo == .y })
        XCTAssertEqual(moves.last?.angle, 90)
    }

    func testStepsAreAtMostTheChunk() {
        var angle = 80
        for move in walk(plan(chunk: 3), from: (90, 80)) {
            XCTAssertLessThanOrEqual(abs(move.angle - angle), 3)
            angle = move.angle
        }
        XCTAssertEqual(angle, 90)
    }

    func testNothingToDoWhenAlreadyThere() {
        XCTAssertTrue(walk(plan(), from: (90, 90)).isEmpty)
    }

    func testAnApproachFromTheWrongSideGoesPastFirst() {
        // The servo last turned up (+1) onto 90; it is now above 90, so a plain return would
        // arrive going down. It goes to 90 - 3 first, then comes up.
        let moves = walk(plan(moved: (false, true), direction: (0, 1)), from: (90, 99))
        let angles = moves.map(\.angle)
        XCTAssertEqual(angles.min(), 87)
        XCTAssertEqual(angles.last, 90)
        let low = angles.firstIndex(of: 87)!
        XCTAssertTrue(angles[low...].allSatisfy { $0 >= 87 })
        XCTAssertEqual(angles[low + 1], 90, "one step back up onto it")
    }

    func testAnApproachFromTheRightSideGoesStraightThere() {
        // Last turned up (+1) onto 90 and now below it: the return also arrives going up.
        let moves = walk(plan(moved: (false, true), direction: (0, 1)), from: (90, 80))
        XCTAssertEqual(moves.map(\.angle).max(), 90)
        XCTAssertTrue(moves.allSatisfy { $0.angle <= 90 })
    }

    func testANeverMovedServoGetsNoOvershoot() {
        let moves = walk(plan(moved: (false, true), direction: (0, 0)), from: (90, 99))
        XCTAssertEqual(moves.map(\.angle).min(), 90)
    }

    func testTheOvershootIsClampedAtALimit() {
        // The saved angle sits on the limit: there is no room past it, so it goes straight.
        let limits = StageLimits(yMin: 90, yMax: 180)
        let moves = walk(
            plan(limits: limits, moved: (false, true), direction: (0, 1)), from: (90, 99))
        XCTAssertEqual(moves.map(\.angle).min(), 90)
        // Room for only 1 degree: it goes past by that much.
        let tight = StageLimits(yMin: 89, yMax: 180)
        let near = walk(plan(limits: tight, moved: (false, true), direction: (0, 1)), from: (90, 99))
        XCTAssertEqual(near.map(\.angle).min(), 89)
        XCTAssertEqual(near.last?.angle, 90)
    }
}
