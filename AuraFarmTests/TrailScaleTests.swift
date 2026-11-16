import XCTest

@testable import AuraFarm

final class TrailScaleTests: XCTestCase {
    func testNeverBelowTheMinimum() {
        XCTAssertEqual(TrailScale.reach(for: []), 3)
        XCTAssertEqual(TrailScale.reach(for: [CGPoint(x: 1, y: -1.5)]), 3)
    }

    func testGrowsToFitInWholeFrames() {
        XCTAssertEqual(TrailScale.reach(for: [CGPoint(x: 0, y: 3.2)]), 5)
        XCTAssertEqual(TrailScale.reach(for: [CGPoint(x: -5, y: 0)]), 6)
    }
}
