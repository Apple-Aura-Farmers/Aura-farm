import XCTest

@testable import AuraFarm

/// The cover slip's top-left corner on column 1. The halves across the heading differ clearly
/// (the left edge is inside the side half). Phase 2k accepted that as a corner whenever the low
/// side faced a known edge close by; Phase 2l also needs quarter evidence: the edge ahead runs
/// across the far side too, the sample is still there behind away from the edge, and the whole
/// box dropped. failed_edge_detection.csv, 13.5 to 15.0 s: ahead 60, behind 660, side halves
/// 600 against 90; the 15 Nov corner took the box from about 1050 to 350.
final class CornerEdgeTests: XCTestCase {
    private let route = ScriptedRoute()
    private let towardLeft = CGPoint(x: -1, y: 0)

    /// Column 1 going up for 3 s at box sharpness 1050 (the median the corner is judged against),
    /// then 1.5 s still with the readings below.
    private func corner(
        lowSideLeft: Bool = true, ahead: Double = 60, aheadAway: Double? = 70,
        aheadToward: Double? = 50, behindAway: Double? = 1300, behindToward: Double? = 120,
        box: Double = 350, direction: CGPoint? = nil, route run: ScriptedRoute? = nil
    ) {
        let route = run ?? self.route
        route.startColumnOne()
        route.feed(ScriptedRoute.Frame(box: 1050), move: ScriptedRoute.up, times: 30)
        route.feed(
            ScriptedRoute.Frame(
                ahead: ahead, behind: 660, sideA: lowSideLeft ? 90 : 600,
                sideB: lowSideLeft ? 600 : 90, still: true, sideDirection: direction ?? towardLeft,
                box: box, aheadAway: aheadAway, aheadToward: aheadToward, behindAway: behindAway,
                behindToward: behindToward), times: 15)
    }

    private func lastReasons(_ route: ScriptedRoute) -> Set<String> {
        Set(route.steps.suffix(15).map(\.edge.reason))
    }

    func testTheRealCornerIsConfirmedWithReasonCornerAndTheColumnTurns() throws {
        corner()
        XCTAssertEqual(route.guide.edgesReached, 2, "column 1's edge at the top")
        XCTAssertTrue(route.steps.contains { $0.edge.reason == "corner" })
        XCTAssertNotEqual(route.last.stateName, "column 1 up")
        XCTAssertEqual(
            try XCTUnwrap(route.steps.last { $0.edge.cornerBoxShare != nil }?.edge.cornerBoxShare),
            350.0 / 1050, accuracy: 0.01)
    }

    func testASparsePatchAheadOnColumnOneIsCornerRejectedAndNoEdge() {
        // Ahead half 100, aheadAway 110, behindAway 1200, the box at 0.75 of its median.
        corner(ahead: 100, aheadAway: 110, behindAway: 1200, box: 0.75 * 1050)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(route), ["corner_rejected"])
        XCTAssertEqual(route.last.stateName, "column 1 up")
    }

    func testARichAheadAwayQuarterIsCornerRejected() {
        corner(aheadAway: 400)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(route), ["corner_rejected"])
    }

    func testNoSampleBehindAwayFromTheEdgeIsCornerRejected() {
        corner(behindAway: 90)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(route), ["corner_rejected"])
    }

    func testMissingQuarterDataIsCornerRejected() {
        corner(aheadAway: nil, behindAway: nil)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(route), ["corner_rejected"])
    }

    func testTheLowSideAwayFromTheEdgeStaysASideImbalance() {
        corner(lowSideLeft: false)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(route), ["side_imbalance"])
        XCTAssertEqual(route.last.stateName, "column 1 up")
    }

    func testAColumnBeyondTheReachOfEveryKnownEdgeStaysASideImbalance() {
        var thresholds = GuidedSweepThresholds()
        thresholds.sideEdgeReachFields = 0.3  // column 1 sits 0.6 from the left edge
        let far = ScriptedRoute()
        far.guide = GuidedSweep(thresholds: thresholds)
        corner(route: far)
        XCTAssertEqual(far.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(far), ["side_imbalance"])
    }

    func testWithoutTheSideDirectionItIsRejectedAsBefore() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 4)
        route.feed(
            ScriptedRoute.Frame(ahead: 60, behind: 660, sideA: 90, sideB: 600, still: true),
            times: 15)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(lastReasons(route), ["side_imbalance"])
    }

    func testCornerRejectedGetsAFrameLikeTheOtherEdgeReasons() {
        XCTAssertTrue(SnapshotTrigger.reasons.contains("corner_rejected"))
    }
}
