import XCTest

@testable import AuraFarm

final class StageHandControlTests: XCTestCase {
    private func directions(flipX: Bool = false, flipY: Bool = false) -> StageArrowDirections {
        StageArrowDirections(flipX: flipX, flipY: flipY)
    }

    func testLeftAndRightAreAlwaysXAndUpAndDownAlwaysY() {
        XCTAssertEqual(StageArrow.left.axis, .x)
        XCTAssertEqual(StageArrow.right.axis, .x)
        XCTAssertEqual(StageArrow.up.axis, .y)
        XCTAssertEqual(StageArrow.down.axis, .y)
    }

    func testNotFlippedRightAndUpAreMoreDegrees() {
        let d = directions()
        XCTAssertEqual(d.sign(.right), 1)
        XCTAssertEqual(d.sign(.left), -1)
        XCTAssertEqual(d.sign(.up), 1)
        XCTAssertEqual(d.sign(.down), -1)
    }

    func testEachFlipTurnsOnlyItsOwnPairRound() {
        let x = directions(flipX: true)
        XCTAssertEqual(x.sign(.right), -1)
        XCTAssertEqual(x.sign(.left), 1)
        XCTAssertEqual(x.sign(.up), 1)
        let y = directions(flipY: true)
        XCTAssertEqual(y.sign(.up), -1)
        XCTAssertEqual(y.sign(.down), 1)
        XCTAssertEqual(y.sign(.right), 1)
    }

    func testNextAngleIsClampedAndNilAtTheEnd() {
        let d = directions()
        let limits = StageLimits(xMin: 10, xMax: 170, yMin: 20, yMax: 160)
        XCTAssertEqual(d.nextAngle(.right, from: 90, step: 3, limits: limits), 93)
        XCTAssertEqual(d.nextAngle(.left, from: 90, step: 3, limits: limits), 87)
        XCTAssertEqual(d.nextAngle(.right, from: 168, step: 3, limits: limits), 170, "clamped")
        XCTAssertNil(d.nextAngle(.right, from: 170, step: 3, limits: limits))
        XCTAssertNil(d.nextAngle(.left, from: 10, step: 3, limits: limits))
        XCTAssertNil(d.nextAngle(.up, from: 160, step: 3, limits: limits))
        XCTAssertNil(d.nextAngle(.down, from: 20, step: 3, limits: limits))
        XCTAssertEqual(d.nextAngle(.left, from: 170, step: 3, limits: limits), 167, "the other way is free")
    }

    func testOnlyTheArrowTowardTheLimitIsDisabled() {
        let d = directions()
        let limits = StageLimits()
        let control = StageHandControl()
        func enabled(_ a: StageArrow) -> Bool {
            control.enabled(a, directions: d, angles: (180, 90), step: 3, limits: limits)
        }
        XCTAssertFalse(enabled(.right), "X is at 180")
        XCTAssertTrue(enabled(.left))
        XCTAssertTrue(enabled(.up))
        XCTAssertTrue(enabled(.down))
    }

    func testOneArrowAtATime() {
        var control = StageHandControl()
        XCTAssertTrue(control.press(.right))
        XCTAssertFalse(control.press(.up), "another arrow is refused")
        XCTAssertFalse(control.press(.left))
        let d = directions()
        XCTAssertFalse(
            control.enabled(.up, directions: d, angles: (90, 90), step: 3, limits: StageLimits()))
        XCTAssertTrue(
            control.enabled(.right, directions: d, angles: (90, 90), step: 3, limits: StageLimits()))
        // Released, but the move has not settled: the others stay off.
        XCTAssertTrue(control.wantsMove)
        control.sent()
        control.release()
        XCTAssertEqual(control.active, .right)
        XCTAssertFalse(control.press(.up))
        control.settled()
        XCTAssertNil(control.active)
        XCTAssertTrue(control.press(.up))
    }

    func testTheSameArrowMayBePressedAgainAndATapIsOneStep() {
        var control = StageHandControl()
        XCTAssertTrue(control.press(.down))
        XCTAssertTrue(control.wantsMove)
        control.sent()
        control.release()
        XCTAssertFalse(control.wantsMove, "a tap is one step: nothing follows the first")
        // Pressed again while the step is still under way: it waits for the settle.
        XCTAssertTrue(control.press(.down))
        XCTAssertFalse(control.wantsMove, "one move in flight, never a queue")
        control.settled()
        XCTAssertTrue(control.wantsMove)
        control.sent()
        control.release()
        control.settled()
        XCTAssertNil(control.active)
    }

    func testAPressThatStaysDownGoesOnOneMoveAtATime() {
        var control = StageHandControl()
        XCTAssertTrue(control.press(.left))
        for _ in 0..<4 {
            XCTAssertTrue(control.wantsMove)
            control.sent()
            XCTAssertFalse(control.wantsMove)
            control.settled()
        }
        control.release()
        XCTAssertNil(control.active)
        XCTAssertFalse(control.wantsMove)
    }

    func testAtALimitNothingIsSentAndReleaseFreesTheLock() {
        var control = StageHandControl()
        XCTAssertTrue(control.press(.right))
        control.blocked()
        XCTAssertFalse(control.wantsMove)
        XCTAssertEqual(control.active, .right, "still down")
        control.release()
        XCTAssertNil(control.active)
    }
}
