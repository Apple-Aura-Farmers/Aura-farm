import XCTest

@testable import AuraFarm

final class StageZigzagTests: XCTestCase {
    private func mapping(
        xVector: CGPoint = CGPoint(x: 0.2, y: 0), yVector: CGPoint = CGPoint(x: 0, y: 0.2),
        ySlack: Double = 0
    ) -> StageServoMapping {
        let axes = StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!
        return StageServoMapping(
            x: xVector, y: yVector, swapped: false, axes: axes, xSlackDegrees: 0,
            ySlackDegrees: ySlack)
    }

    /// Plays the caller: moves settle at once, dwells end, and `edge` can make a dwell an edge.
    private func simulate(
        _ zigzag: inout StageZigzag, angles: inout (x: Int, y: Int),
        edge: (_ column: Int, _ dwell: Int, _ legAngle: Int) -> Bool = { _, _, _ in false },
        stopAfterColumn: Int = .max
    ) -> [StageZigzagAction] {
        var actions: [StageZigzagAction] = []
        var event: StageZigzagEvent?
        var dwell = 0
        for _ in 0..<20_000 {
            guard let action = zigzag.next(angles: angles, event: event) else {
                XCTFail("stuck after \\(actions.count) actions")
                return actions
            }
            event = nil
            actions.append(action)
            switch action {
            case .moveTo(let servo, let angle):
                if servo == .x { angles.x = angle } else { angles.y = angle }
                event = .settled
            case .dwell:
                dwell += 1
                let leg = zigzag.plan.legServo == .x ? angles.x : angles.y
                event = edge(zigzag.column, dwell, leg) ? .edge : .dwellDone
            case .columnStarted(let n):
                dwell = 0
                if n > stopAfterColumn { return actions }
            case .columnEnded: break
            case .finished: return actions
            }
        }
        XCTFail("did not finish")
        return actions
    }

    private func legAngles(_ actions: [StageZigzagAction], _ plan: StageZigzagPlan, column: Int)
        -> [Int]
    {
        var inColumn = 0
        var angles: [Int] = []
        for action in actions {
            if case .columnStarted(let n) = action { inColumn = n }
            if case .moveTo(let servo, let angle) = action, servo == plan.legServo, inColumn == column {
                angles.append(angle)
            }
        }
        return angles
    }

    func testStepSizesFromFieldsPerDegreeNeverBelowMinChunk() throws {
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: mapping(), minChunk: 1))
        XCTAssertEqual(plan.legServo, .y)
        XCTAssertEqual(plan.columnStepDegrees, 4)  // 0.8 field at 0.2 per degree
        XCTAssertEqual(plan.spotStepDegrees, 4)
        let coarse = try XCTUnwrap(
            StageZigzagPlan(
                mapping: mapping(xVector: CGPoint(x: 1, y: 0), yVector: CGPoint(x: 0, y: 1)),
                minChunk: 2))
        XCTAssertEqual(coarse.columnStepDegrees, 2)  // 0.8 rounds to 1, raised to the minimum
        XCTAssertEqual(coarse.spotStepDegrees, 2)
    }

    func testSwappedServosWalkTheColumnWithTheVerticalOne() throws {
        let swapped = StageServoMapping(
            x: CGPoint(x: 0, y: 0.2), y: CGPoint(x: 0.2, y: 0), swapped: true,
            axes: StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!)
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: swapped, minChunk: 1))
        XCTAssertEqual(plan.legServo, .x)
        XCTAssertEqual(plan.stepServo, .y)
    }

    func testColumnsZigZag() throws {
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: mapping(), minChunk: 1))
        var zigzag = StageZigzag(plan: plan, dwellSeconds: 1)
        var angles = (x: 90, y: 90)
        let actions = simulate(&zigzag, angles: &angles, stopAfterColumn: 2)
        let first = legAngles(actions, plan, column: 1)
        let second = legAngles(actions, plan, column: 2)
        // Up from 0 in spot steps, then back down from the top.
        XCTAssertEqual(first.first, 4)
        XCTAssertEqual(first.last, 180)
        XCTAssertEqual(first, first.sorted())
        XCTAssertEqual(second.first, 176)
        XCTAssertEqual(second.last, 0)
        XCTAssertEqual(second, second.sorted(by: >))
        // The step servo moved one column step between them.
        XCTAssertTrue(actions.contains(.moveTo(servo: .x, angle: 4)))
    }

    func testSlackOnlyOnTheFirstMoveAfterAReversal() throws {
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: mapping(ySlack: 5), minChunk: 1))
        var zigzag = StageZigzag(plan: plan, dwellSeconds: 1)
        var angles = (x: 90, y: 90)
        let actions = simulate(&zigzag, angles: &angles, stopAfterColumn: 3)
        let first = legAngles(actions, plan, column: 1)
        XCTAssertEqual(Array(first.prefix(3)), [9, 13, 17])  // 4 + 5 slack, then plain steps
        let second = legAngles(actions, plan, column: 2)
        XCTAssertEqual(Array(second.prefix(3)), [171, 167, 163])
    }

    func testAnEdgeEndsTheLegAndNarrowsLaterOnes() throws {
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: mapping(), minChunk: 1))
        var zigzag = StageZigzag(plan: plan, dwellSeconds: 1)
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles,
            edge: { column, _, leg in column == 1 && leg >= 40 }, stopAfterColumn: 3)
        let first = legAngles(actions, plan, column: 1)
        XCTAssertEqual(first.last, 40)
        // The third column climbs again, but only to the edge plus the margin.
        let third = legAngles(actions, plan, column: 3)
        XCTAssertEqual(third.last, 43)
        XCTAssertLessThanOrEqual(third.max() ?? 0, 43)
    }

    func testFinishesAtTheStepServosEnd() throws {
        // A wide column step reaches the far end in a few columns.
        let wide = mapping(xVector: CGPoint(x: 0.01, y: 0))
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: wide, minChunk: 1))
        XCTAssertEqual(plan.columnStepDegrees, 80)
        var zigzag = StageZigzag(plan: plan, dwellSeconds: 1)
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, edge: { _, dwell, _ in dwell >= 2 })
        XCTAssertEqual(actions.last, .finished("end of range"))
        XCTAssertEqual(
            actions.filter { if case .columnStarted = $0 { true } else { false } }.count, 4)
    }

    func testAnEdgeAtTheStartOfALaterColumnFinishes() throws {
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: mapping(), minChunk: 1))
        var zigzag = StageZigzag(plan: plan, dwellSeconds: 1)
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles,
            edge: { column, dwell, _ in column == 1 ? dwell >= 3 : true })
        guard case .finished(let reason)? = actions.last else { return XCTFail("did not finish") }
        XCTAssertTrue(reason.hasPrefix("edge at the start of column 2"))
    }
}
