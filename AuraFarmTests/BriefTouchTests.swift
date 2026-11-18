import XCTest

@testable import AuraFarm

/// Brief-touch spots: a spot is ticked by passing through its window slowly enough, not by
/// holding still. Scripted readings through `GuidedSweep`, 10 a second, in screen axes.
final class BriefTouchTests: XCTestCase {
    private let step = 0.05
    private var route = ScriptedRoute()

    private func briefRoute() -> ScriptedRoute {
        var thresholds = GuidedSweepThresholds()
        thresholds.alignment.spotMode = .briefTouch
        let route = ScriptedRoute()
        route.guide = GuidedSweep(thresholds: thresholds)
        return route
    }

    override func setUp() {
        route = briefRoute()
        route.startColumnOne()
    }

    private func frame(speed: Double) -> ScriptedRoute.Frame {
        ScriptedRoute.Frame(still: false, speed: speed)
    }

    /// Jumps the view onto the target plus an offset, in one reading.
    private func jump(toTargetPlus offset: CGPoint, speed: Double = 0.05) throws {
        let target = try XCTUnwrap(route.last.target)
        route.feed(
            frame(speed: speed),
            move: CGPoint(
                x: target.x + offset.x - route.position.x, y: target.y + offset.y - route.position.y))
    }

    func testFirstSpotIsTickedWithoutStillnessAndNoHoldIsShown() {
        XCTAssertEqual(route.guide.placements.count, 1)
        XCTAssertFalse(route.instructions.contains { if case .holding = $0 { true } else { false } })
    }

    func testASteadyPassTicksFiveSpotsWithoutStillness() {
        let start = route.guide.placements.count
        for _ in 0..<600 where route.guide.placements.count < start + 5 {
            guard let target = route.last.target else { return XCTFail("no target") }
            let near = hypot(Double(target.x - route.position.x), Double(target.y - route.position.y)) < 0.25
            // 0.5 fields a second; slowing to 0.6 x the touch limit inside the window.
            route.feed(frame(speed: near ? 0.06 : 0.15), move: CGPoint(x: 0, y: -step))
        }
        XCTAssertEqual(route.guide.placements.count, start + 5)
        XCTAssertEqual(route.guide.missedSpots, 0)
    }

    func testAFastPassGivesMissedSpotAndASlowerPassBackTicksIt() throws {
        let count = route.guide.placements.count
        for _ in 0..<60 where route.guide.missedSpots == 0 {
            route.feed(frame(speed: 0.2), move: CGPoint(x: 0, y: -step))
        }
        XCTAssertEqual(route.guide.placements.count, count)
        XCTAssertEqual(route.guide.missedSpots, 1)
        guard case .missedSpot = route.last.instruction else {
            return XCTFail("\(route.last.instruction)")
        }
        XCTAssertEqual(route.last.instruction.csvName, "missed_spot")
        for _ in 0..<80 where route.guide.placements.count == count {
            route.feed(frame(speed: 0.05), move: CGPoint(x: 0, y: step))
        }
        XCTAssertEqual(route.guide.placements.count, count + 1)
        XCTAssertEqual(route.guide.missedSpots, 1, "one missed pass is counted once")
    }

    func testTwoTenthsInsideTheWindowIsNotEnoughAndThreeTenthsIs() throws {
        let count = route.guide.placements.count
        try jump(toTargetPlus: .zero)
        route.feed(frame(speed: 0.05), times: 2)
        XCTAssertEqual(route.guide.placements.count, count, "0.2 s")
        route.feed(frame(speed: 0.05))
        XCTAssertEqual(route.guide.placements.count, count + 1, "0.3 s")
    }

    func testDriftingSidewaysBeyondTheToleranceGivesNoTick() throws {
        let count = route.guide.placements.count
        try jump(toTargetPlus: CGPoint(x: 0.3, y: 0))
        route.feed(frame(speed: 0.05), times: 12)
        XCTAssertEqual(route.guide.placements.count, count)
        try jump(toTargetPlus: CGPoint(x: 0.15, y: 0))
        route.feed(frame(speed: 0.05), times: 4)
        XCTAssertEqual(route.guide.placements.count, count + 1)
    }

    func testNotTrackingInsideTheWindowGivesNoTick() throws {
        let count = route.guide.placements.count
        try jump(toTargetPlus: .zero)
        route.feed(ScriptedRoute.Frame(tracking: .matching, still: true, speed: 0.0), times: 12)
        XCTAssertEqual(route.guide.placements.count, count)
    }

    func testTooFastInsideTheWindowGivesNoTick() throws {
        let count = route.guide.placements.count
        try jump(toTargetPlus: .zero, speed: 0.12)
        route.feed(frame(speed: 0.12), times: 6)
        XCTAssertEqual(route.guide.placements.count, count)
    }

    /// Readings of `.edgeAhead` (still) until the leg's edge counts, from the reading it began.
    private func readingsToConfirmEdge(_ route: ScriptedRoute) -> Int {
        route.feed(frame(speed: 0.05), move: CGPoint(x: 0, y: -0.1), times: 4)
        let before = route.guide.edgesReached + route.guide.edgesGoneBack
        var readings = 0
        while route.guide.edgesReached + route.guide.edgesGoneBack == before, readings < 60 {
            route.feed(.edgeAhead)
            readings += 1
        }
        return readings
    }

    func testAnEdgeMidLegStillNeedsTwoSecondsStill() {
        let hold = ScriptedRoute()
        hold.startColumnOne()
        let holdReadings = readingsToConfirmEdge(hold)
        let briefReadings = readingsToConfirmEdge(route)
        XCTAssertEqual(briefReadings, holdReadings, "brief touch does not shorten the edge wait")
        XCTAssertGreaterThanOrEqual(briefReadings, 19, "about 2 s of stillness")
        XCTAssertLessThan(briefReadings, 60)
    }
}
