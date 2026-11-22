import XCTest

@testable import AuraFarm

final class StageZigzagTests: XCTestCase {
    private func mapping(
        xVector: CGPoint = CGPoint(x: 0.2, y: 0), yVector: CGPoint = CGPoint(x: 0, y: 0.2)
    ) -> StageServoMapping {
        let axes = StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!
        return StageServoMapping(
            x: xVector, y: yVector, swapped: false, axes: axes, xSlackDegrees: 0)
    }

    /// Plays the caller: moves settle at once, dwells end, `edge` can make a dwell an edge, and
    /// `picture` says where the tracker would see the picture (nil: not tracking).
    private func simulate(
        _ zigzag: inout StageZigzag, angles: inout (x: Int, y: Int),
        edge: (_ column: Int, _ dwell: Int, _ legAngle: Int) -> Bool = { _, _, _ in false },
        picture: ((x: Int, y: Int)) -> CGPoint? = { _ in nil },
        stopAfterColumn: Int = .max, onMove: (Int) -> Void = { _ in }
    ) -> [StageZigzagAction] {
        var actions: [StageZigzagAction] = []
        var event: StageZigzagEvent?
        var dwell = 0
        for _ in 0..<50_000 {
            guard
                let action = zigzag.next(angles: angles, event: event, tracked: picture(angles))
            else {
                XCTFail("stuck after \(actions.count) actions")
                return actions
            }
            event = nil
            actions.append(action)
            switch action {
            case .moveTo(let servo, let angle):
                onMove(abs(angle - (servo == .x ? angles.x : angles.y)))
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

    /// The picture of a mapping with the given fields per degree: y moves it down, x right.
    private func picture(x: Double, y: Double) -> ((x: Int, y: Int)) -> CGPoint? {
        { CGPoint(x: Double($0.x) * x, y: Double($0.y) * y) }
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

    /// The leg servo's angle at each dwell of a column.
    private func stopAngles(
        _ actions: [StageZigzagAction], _ plan: StageZigzagPlan, start: Int, column: Int
    ) -> [Int] {
        var inColumn = 0
        var current = start
        var stops: [Int] = []
        for action in actions {
            switch action {
            case .columnStarted(let n): inColumn = n
            case .moveTo(let servo, let angle) where servo == plan.legServo: current = angle
            case .dwell where inColumn == column: stops.append(current)
            default: break
            }
        }
        return stops
    }

    private func makeZigzag(
        _ mapping: StageServoMapping, chunk: Int = 2
    ) throws -> StageZigzag {
        StageZigzag(
            plan: try XCTUnwrap(StageZigzagPlan(mapping: mapping)), chunkDegrees: chunk,
            dwellSeconds: 1)
    }

    func testFallbackDegreesNeverBelowTheChunk() throws {
        let fine = try makeZigzag(mapping(), chunk: 1)
        XCTAssertEqual(fine.plan.legServo, .y)
        XCTAssertEqual(fine.legFallbackDegrees, 4)  // 0.8 field at 0.2 per degree
        XCTAssertEqual(fine.columnFallbackDegrees, 4)
        let coarse = try makeZigzag(
            mapping(xVector: CGPoint(x: 1, y: 0), yVector: CGPoint(x: 0, y: 1)), chunk: 2)
        XCTAssertEqual(coarse.legFallbackDegrees, 2)  // 0.8 rounds to 1, raised to the chunk
        XCTAssertEqual(coarse.columnFallbackDegrees, 2)
    }

    func testSwappedServosWalkTheColumnWithTheVerticalOne() throws {
        let swapped = StageServoMapping(
            x: CGPoint(x: 0, y: 0.2), y: CGPoint(x: 0.2, y: 0), swapped: true,
            axes: StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!)
        let plan = try XCTUnwrap(StageZigzagPlan(mapping: swapped))
        XCTAssertEqual(plan.legServo, .x)
        XCTAssertEqual(plan.stepServo, .y)
    }

    func testNoMoveIsLongerThanTheChunkEvenWithATinyMapping() throws {
        // Run 5: 0.023 fields per degree used to give 34° spot steps and jumps to 0 and 180.
        var zigzag = try makeZigzag(
            mapping(xVector: CGPoint(x: 0.023, y: 0), yVector: CGPoint(x: 0, y: 0.023)))
        var angles = (x: 90, y: 90)
        var longest = 0
        _ = simulate(
            &zigzag, angles: &angles,
            picture: picture(x: 0.023, y: 0.023), stopAfterColumn: 3,
            onMove: { longest = max(longest, $0) })
        XCTAssertLessThanOrEqual(longest, 2)
        XCTAssertGreaterThan(longest, 0)
    }

    func testColumnsZigZag() throws {
        var zigzag = try makeZigzag(mapping())
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, picture: picture(x: 0.2, y: 0.2), stopAfterColumn: 2)
        let first = legAngles(actions, zigzag.plan, column: 1)
        let second = legAngles(actions, zigzag.plan, column: 2)
        // Up from 0 in chunks, then back down from the top.
        XCTAssertEqual(first.first, 2)
        XCTAssertEqual(first.last, 180)
        XCTAssertEqual(first, first.sorted())
        XCTAssertEqual(second.first, 178)
        XCTAssertEqual(second.last, 0)
        XCTAssertEqual(second, second.sorted(by: >))
        // The step servo walked a column step (4° at 0.2 per degree) between them.
        XCTAssertTrue(actions.contains(.moveTo(servo: .x, angle: 4)))
    }

    func testStopsComeEveryStepFieldsOfTrackedTravel() throws {
        // 0.05 per degree: 0.8 field is 16°, in 2° chunks, whatever the plan thought.
        var zigzag = try makeZigzag(mapping())  // the plan's 0.2 is stale, the picture is 0.05
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, picture: picture(x: 0.05, y: 0.05), stopAfterColumn: 2)
        let stops = stopAngles(actions, zigzag.plan, start: 0, column: 1)
        XCTAssertEqual(Array(stops.prefix(4)), [0, 16, 32, 48])
    }

    func testWithoutTrackingTheDegreeFallbackSpacingIsUsed() throws {
        var coarse = try makeZigzag(mapping(), chunk: 2)  // 4° fallback
        var angles = (x: 90, y: 90)
        var actions = simulate(&coarse, angles: &angles, stopAfterColumn: 2)
        XCTAssertEqual(Array(stopAngles(actions, coarse.plan, start: 0, column: 1).prefix(3)), [0, 4, 8])
        // A fallback under the chunk is raised to it.
        var fine = try makeZigzag(
            mapping(xVector: CGPoint(x: 1, y: 0), yVector: CGPoint(x: 0, y: 1)), chunk: 3)
        angles = (x: 90, y: 90)
        actions = simulate(&fine, angles: &angles, stopAfterColumn: 2)
        XCTAssertEqual(Array(stopAngles(actions, fine.plan, start: 0, column: 1).prefix(3)), [0, 3, 6])
    }

    func testColumnStepEndsAfterStepFieldsOfSidewaysTravel() throws {
        var zigzag = try makeZigzag(mapping())  // stale plan; picture moves 0.05 per degree sideways
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, picture: picture(x: 0.05, y: 0.05), stopAfterColumn: 2)
        // 16° of x at 0.05 per degree is 0.8 field, walked in 2° steps from 0.
        let xMoves = actions.compactMap { action -> Int? in
            if case .moveTo(.x, let angle) = action { return angle }
            return nil
        }
        // The first x moves are the approach from 90 down to 0; the column step follows it.
        let columnStep = Array(xMoves.drop { $0 != 0 }.dropFirst())
        XCTAssertEqual(columnStep, [2, 4, 6, 8, 10, 12, 14, 16])
    }

    func testColumnStepStopsAtTwiceTheFallbackWithoutTracking() throws {
        // A picture that never moves sideways: 0.2 per degree gives a 4° fallback, 8° cap.
        var zigzag = try makeZigzag(mapping(), chunk: 2)
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, picture: { _ in CGPoint(x: 0, y: 0) }, stopAfterColumn: 1)
        let xMoves = actions.compactMap { action -> Int? in
            if case .moveTo(.x, let angle) = action { return angle }
            return nil
        }
        XCTAssertEqual(Array(xMoves.drop { $0 != 0 }.dropFirst()), [2, 4, 6, 8])
        // Without a position it ends at the plain fallback instead.
        var blind = try makeZigzag(mapping(), chunk: 2)
        angles = (x: 90, y: 90)
        let blindActions = simulate(&blind, angles: &angles, stopAfterColumn: 1)
        let blindX = blindActions.compactMap { action -> Int? in
            if case .moveTo(.x, let angle) = action { return angle }
            return nil
        }
        XCTAssertEqual(Array(blindX.drop { $0 != 0 }.dropFirst()), [2, 4])
    }

    func testALiveScaleUpdateChangesTheNextLegsFallback() throws {
        var zigzag = try makeZigzag(mapping(), chunk: 2)  // 4° fallback
        var angles = (x: 90, y: 90)
        _ = simulate(&zigzag, angles: &angles, stopAfterColumn: 1)
        zigzag.setFieldsPerDegree(x: 0.2, y: 0.1)  // really 0.1 per degree: 8°
        XCTAssertEqual(zigzag.legFallbackDegrees, 8)
        let legStart = angles.y
        let actions = simulate(&zigzag, angles: &angles, stopAfterColumn: 2)
        let stops = stopAngles(actions, zigzag.plan, start: legStart, column: 0)
        XCTAssertEqual(Array(stops.prefix(3)), [180, 172, 164])
    }

    func testAnEdgeEndsTheLegAndNarrowsLaterOnes() throws {
        var zigzag = try makeZigzag(mapping())
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, edge: { column, _, leg in column == 1 && leg >= 40 },
            picture: picture(x: 0.2, y: 0.2), stopAfterColumn: 3)
        let first = legAngles(actions, zigzag.plan, column: 1)
        XCTAssertEqual(first.last, 40)
        // The third column climbs again, but only to the edge plus the margin.
        let third = legAngles(actions, zigzag.plan, column: 3)
        XCTAssertEqual(third.last, 43)
        XCTAssertLessThanOrEqual(third.max() ?? 0, 43)
    }

    func testFinishesAtTheStepServosEnd() throws {
        // A wide column step reaches the far end in a few columns.
        var zigzag = try makeZigzag(mapping(xVector: CGPoint(x: 0.01, y: 0)))
        XCTAssertEqual(zigzag.columnFallbackDegrees, 80)
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, edge: { _, dwell, _ in dwell >= 2 })
        XCTAssertEqual(actions.last, .finished("end of range"))
        XCTAssertEqual(
            actions.filter { if case .columnStarted = $0 { true } else { false } }.count, 4)
    }

    func testAnEdgeAtTheStartOfALaterColumnFinishes() throws {
        var zigzag = try makeZigzag(mapping())
        var angles = (x: 90, y: 90)
        let actions = simulate(
            &zigzag, angles: &angles, edge: { column, dwell, _ in column == 1 ? dwell >= 3 : true },
            picture: picture(x: 0.2, y: 0.2))
        guard case .finished(let reason)? = actions.last else { return XCTFail("did not finish") }
        XCTAssertTrue(reason.hasPrefix("edge at the start of column 2"))
    }
}
