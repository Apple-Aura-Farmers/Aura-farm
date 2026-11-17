import XCTest

@testable import AuraFarm

/// End run early: now, or after the current column.
final class EarlyEndTests: XCTestCase {
    private func simulator() -> GuideSimulator {
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: 0, width: 2.8, height: 2.4)])
        let simulator = GuideSimulator(drop: drop, start: CGPoint(x: 1.5, y: 1.2))
        simulator.useFullCoverSlip()
        return simulator
    }

    private func runToColumnTwo(_ simulator: GuideSimulator) {
        _ = simulator.run(until: { $0.stateName == "column 2 up" })
    }

    func testEndNowMidLegFinishesWithNoFurtherInstructionsOrSpots() {
        let route = ScriptedRoute()
        route.startColumnOne()
        let spots = route.guide.placements.count
        route.guide.endNow()
        route.feed(ScriptedRoute.Frame(still: true), times: 30)
        XCTAssertTrue(route.guide.isFinished)
        XCTAssertEqual(route.guide.finishReason, .endedByHelper)
        XCTAssertEqual(route.guide.placements.count, spots)
        XCTAssertTrue(route.steps.suffix(30).allSatisfy { $0.instruction == .finished && $0.capture == nil })
    }

    func testEndAfterColumnLetsTheLegReachItsEdgeThenFinishesWithoutAStep() {
        let simulator = simulator()
        runToColumnTwo(simulator)
        simulator.guide.endAfterColumn()
        XCTAssertTrue(simulator.guide.pendingEnd)
        XCTAssertFalse(simulator.guide.isFinished)
        let spots = simulator.guide.placements.count
        let result = simulator.run()
        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.finishReason, .endedByHelper)
        XCTAssertGreaterThan(result.placements.count, spots, "the leg went on and ticked its edge spot")
        XCTAssertFalse(result.states.contains("step right"))
        XCTAssertEqual(result.placements.last?.column, 2)
    }

    func testEndAfterColumnDuringTheLeftEdgeRunEndsAtOnce() {
        let route = ScriptedRoute()
        route.feed(move: ScriptedRoute.left, times: 15)
        XCTAssertEqual(route.last.stateName, "find left edge")
        route.guide.endAfterColumn()
        XCTAssertTrue(route.guide.isFinished)
        XCTAssertEqual(route.guide.finishReason, .endedByHelper)
    }

    func testCancelEndAfterColumnStepsRightAsNormal() {
        let simulator = simulator()
        runToColumnTwo(simulator)
        simulator.guide.endAfterColumn()
        simulator.guide.cancelEndAfterColumn()
        XCTAssertFalse(simulator.guide.pendingEnd)
        let result = simulator.run()
        XCTAssertEqual(result.finishReason, .rightEdge)
        XCTAssertTrue(result.states.contains("column 3 down"))
    }

    func testEndingAfterAFinishChangesNothing() {
        let simulator = simulator()
        let result = simulator.run()
        XCTAssertEqual(result.finishReason, .rightEdge)
        simulator.guide.endNow()
        simulator.guide.endAfterColumn()
        simulator.guide.cancelEndAfterColumn()
        XCTAssertEqual(simulator.guide.finishReason, .rightEdge)
        XCTAssertFalse(simulator.guide.pendingEnd)
    }

    func testEndedByHelperKeepsItsRawValue() throws {
        let data = try JSONEncoder().encode([SweepFinishReason.endedByHelper])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"endedByHelper\"]")
        XCTAssertEqual(try JSONDecoder().decode([SweepFinishReason].self, from: data), [.endedByHelper])
    }
}
