import XCTest

@testable import AuraFarm

/// The coverage picker: the step right uses the chosen spacing; everything else stays.
final class CoverageStepTests: XCTestCase {
    func testEveryThirdColumnStepsTwoPointFourAndStillFinishesAtTheRightEdge() {
        // 6.2 wide: columns at 0.6, 3.0, 5.4; the next step (7.8) is past the right edge.
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: 0, width: 6.2, height: 2.4)])
        let simulator = GuideSimulator(drop: drop, start: CGPoint(x: 3.1, y: 1.2))
        simulator.useFullCoverSlip()
        var thresholds = GuidedSweepThresholds()
        thresholds.fullCoverSlip = true
        thresholds.columnSpacingFields = 2.4
        simulator.guide = GuidedSweep(thresholds: thresholds)
        let result = simulator.run()
        XCTAssertEqual(result.finishReason, .rightEdge)
        let columns = result.states.filter { $0.hasPrefix("column") && !$0.hasSuffix("edge spot") }
        XCTAssertEqual(columns, ["column 1 up", "column 1 down", "column 2 up", "column 3 down"])
        let byColumn = Dictionary(grouping: result.placements, by: \.column)
        let xs = [1, 2, 3].compactMap { byColumn[$0]?.map { Double($0.position.x) }.min() }
        XCTAssertEqual(xs.count, 3)
        guard xs.count == 3 else { return }
        XCTAssertEqual(xs[1] - xs[0], 2.4, accuracy: 0.2)
        XCTAssertEqual(xs[2] - xs[1], 2.4, accuracy: 0.2)
    }
}
