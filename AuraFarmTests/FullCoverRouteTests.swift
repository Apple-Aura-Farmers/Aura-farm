import XCTest

@testable import AuraFarm

/// Phase 2o part C: the route in full-cover-slip mode on a square cover slip filled with sample,
/// with the edge line found on all four sides: the zig-zag as before, but no left-edge recheck and
/// no inward probing, and the right edge line finishes the route.
final class FullCoverRouteTests: XCTestCase {
    /// 2.8 fields wide, so three columns (x = 0.6, 1.4, 2.2) fit and the step right to 3.0 meets
    /// the right edge at 2.8; 2.4 high.
    private func simulate() -> GuideSimulator.Result {
        let drop = SimulatedDrop(
            circles: [], rects: [CGRect(x: 0, y: 0, width: 2.8, height: 2.4)])
        let simulator = GuideSimulator(drop: drop, start: CGPoint(x: 1.5, y: 1.2))
        simulator.useFullCoverSlip()
        return simulator.run()
    }

    func testAThreeColumnRunZigZagsAndFinishesAtTheRightEdgeLine() {
        let result = simulate()
        print("FULLCOVER states:", result.states)
        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.finishReason, .rightEdge)
        let columns = result.states.filter { $0.hasPrefix("column") && !$0.hasSuffix("edge spot") }
        XCTAssertEqual(
            columns,
            [
                "column 1 up", "column 1 down", "column 2 up", "column 3 down",
            ])
    }

    /// Phase 2r part A: after column 1 ends on the bottom edge the step right lands and column 2
    /// goes UP (away from the edge just confirmed), column 3 DOWN, one leg each; no target is
    /// below the bottom edge or above the top one.
    func testAfterTheBottomEdgeColumnTwoGoesUpAndColumnThreeDownWithinTheEdges() {
        let result = simulate()
        let byColumn = Dictionary(grouping: result.placements, by: \.column)
        let ys = { (column: Int) in
            (byColumn[column] ?? []).sorted { $0.order < $1.order }.map { Double($0.position.y) }
        }
        let two = ys(2)
        XCTAssertGreaterThanOrEqual(two.count, 2)
        XCTAssertLessThan(two[1], two[0], "column 2's first target after the landing is above it")
        XCTAssertTrue(zip(two, two.dropFirst()).allSatisfy { $0.1 < $0.0 }, "up only: \(two)")
        let three = ys(3)
        XCTAssertTrue(zip(three, three.dropFirst()).allSatisfy { $0.1 > $0.0 }, "down only: \(three)")
        let all = result.placements.map { Double($0.position.y) }
        XCTAssertGreaterThan(all.min() ?? 0, -0.4)
        XCTAssertLessThan(all.max() ?? 0, 2.4 + 0.4)
    }

    func testNoRecheckTravelAndNoInwardProbe() {
        let result = simulate()
        XCTAssertEqual(result.rechecks, 0)
        XCTAssertEqual(result.failedProbes, 0)
        XCTAssertFalse(result.states.contains { $0.contains("recheck") || $0.contains("probe") })
    }

    func testCapturesAreSpacedEightTenthsOnAnEightTenthsGrid() {
        let result = simulate()
        let byColumn = Dictionary(grouping: result.placements, by: \.column)
        XCTAssertEqual(byColumn.keys.sorted(), [1, 2, 3])
        // Columns 0.8 apart.
        let xs = [1, 2, 3].compactMap { byColumn[$0]?.map { Double($0.position.x) }.min() }
        XCTAssertEqual(xs.count, 3)
        guard xs.count == 3 else { return }
        XCTAssertEqual(xs[1] - xs[0], 0.8, accuracy: 0.15)
        XCTAssertEqual(xs[2] - xs[1], 0.8, accuracy: 0.15)
        // Along each column consecutive spots are 0.8 apart, within the alignment tolerance of
        // 0.15 each end; the spot at an edge (taken where the leg ends) may come a little closer.
        for (column, placements) in byColumn {
            let ys = placements.sorted { $0.order < $1.order }.map { Double($0.position.y) }
            let gaps = zip(ys, ys.dropFirst()).map { abs($0.1 - $0.0) }
            XCTAssertTrue(gaps.allSatisfy { $0 > 0.45 && $0 < 1.3 }, "column \(column): \(gaps)")
            XCTAssertTrue(gaps.contains { abs($0 - 0.8) < 0.15 }, "column \(column): \(gaps)")
        }
        XCTAssertGreaterThanOrEqual(result.coverage, 0.85)
    }
}
