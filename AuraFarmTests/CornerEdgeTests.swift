import XCTest

@testable import AuraFarm

/// Phase 2k part A: the cover slip's top-left corner on column 1. The halves across the heading
/// differ clearly (the left edge is inside the side half), which is a corner, not a side
/// drifting in, when the low side faces a known edge close by. failed_edge_detection.csv,
/// 13.5 to 15.0 s: ahead 60, behind 660, side halves 600 against 90.
final class CornerEdgeTests: XCTestCase {
    private let route = ScriptedRoute()
    private let towardLeft = CGPoint(x: -1, y: 0)

    private func corner(lowSideLeft: Bool, times: Int = 15) {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 4)
        // Side A lies on the screen left; it is the low one when the corner is on the left.
        route.feed(
            ScriptedRoute.Frame(
                ahead: 60, behind: 660, sideA: lowSideLeft ? 90 : 600, sideB: lowSideLeft ? 600 : 90,
                still: true, sideDirection: towardLeft), times: times)
    }

    func testTheCornerAtTheLeftEdgeIsConfirmedAndTheColumnTurns() {
        corner(lowSideLeft: true)
        XCTAssertEqual(route.guide.edgesReached, 2, "column 1's edge at the top")
        XCTAssertTrue(route.steps.contains { $0.edge.reason == "corner" })
        XCTAssertNotEqual(route.last.stateName, "column 1 up")
    }

    func testTheSameReadingsWithTheLowSideAwayFromTheEdgeStayASideImbalance() {
        corner(lowSideLeft: false)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertTrue(route.steps.suffix(15).allSatisfy { $0.edge.reason == "side_imbalance" })
        XCTAssertEqual(route.last.stateName, "column 1 up")
    }

    func testAColumnBeyondTheReachOfEveryKnownEdgeStaysASideImbalance() {
        var thresholds = GuidedSweepThresholds()
        thresholds.sideEdgeReachFields = 0.3  // column 1 sits 0.6 from the left edge
        let far = ScriptedRoute()
        far.guide = GuidedSweep(thresholds: thresholds)
        far.startColumnOne()
        far.feed(move: ScriptedRoute.up, times: 4)
        far.feed(
            ScriptedRoute.Frame(
                ahead: 60, behind: 660, sideA: 90, sideB: 600, still: true,
                sideDirection: towardLeft), times: 15)
        XCTAssertEqual(far.guide.edgesReached, 1)
        XCTAssertTrue(far.steps.suffix(15).allSatisfy { $0.edge.reason == "side_imbalance" })
    }

    func testWithoutTheSideDirectionItIsRejectedAsBefore() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 4)
        route.feed(
            ScriptedRoute.Frame(ahead: 60, behind: 660, sideA: 90, sideB: 600, still: true),
            times: 15)
        XCTAssertEqual(route.guide.edgesReached, 1)
    }
}
