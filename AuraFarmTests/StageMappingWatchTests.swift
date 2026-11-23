import XCTest

@testable import AuraFarm

final class StageMappingWatchTests: XCTestCase {
    private let mapping: StageServoMapping = {
        let axes = StageAxes(xDirection: CGPoint(x: 1, y: 0), yDirection: CGPoint(x: 0, y: 1))!
        return StageServoMapping(
            x: CGPoint(x: 0.2, y: 0), y: CGPoint(x: 0, y: 0.2), swapped: false, axes: axes)
    }()

    private func record(
        _ watch: inout StageMappingWatch, degrees: Double = 3, dx: Double, lost: Bool = false
    ) -> StageMappingCorrection? {
        watch.record(
            servo: .x, degrees: degrees, delta: CGPoint(x: dx, y: 0), trackingLost: lost,
            mapping: mapping)
    }

    func testThreeOppositeMovesFlip() {
        var w = StageMappingWatch()
        XCTAssertNil(record(&w, dx: -0.6))
        XCTAssertNil(record(&w, dx: -0.6))
        guard case .flip(.x, let vector)? = record(&w, dx: -0.6) else {
            return XCTFail("expected a flip")
        }
        XCTAssertEqual(Double(vector.x), -0.2, accuracy: 1e-9)
    }

    func testNoiseDoesNothing() {
        var w = StageMappingWatch()
        for _ in 0..<5 { XCTAssertNil(record(&w, dx: -0.04)) }
    }

    func testMovesWithTheMappingNeverFlip() {
        var w = StageMappingWatch()
        for _ in 0..<8 { XCTAssertNil(record(&w, dx: 0.6)) }
    }

    func testFitBasedFlip() throws {
        var w = StageMappingWatch()
        XCTAssertNil(record(&w, dx: -0.6))
        XCTAssertNil(record(&w, dx: -0.6))
        XCTAssertNil(record(&w, dx: 0.3))
        let fix = try XCTUnwrap(record(&w, dx: -0.6))
        guard case .flip(.x, let vector) = fix else { return XCTFail("not a flip: \(fix)") }
        XCTAssertEqual(Double(vector.x), -0.125, accuracy: 1e-9)
    }

    func testScaleBlendsHalfWay() throws {
        var w = StageMappingWatch()
        // 1.2 fields for 3 degrees is 0.4 per degree, twice the mapping's 0.2.
        for _ in 0..<5 { XCTAssertNil(record(&w, dx: 1.2)) }
        let fix = try XCTUnwrap(record(&w, dx: 1.2))
        guard case .scale(.x, let vector) = fix else { return XCTFail("not a scale: \(fix)") }
        XCTAssertEqual(Double(vector.x), 0.3, accuracy: 1e-9)
    }

    func testSmallDifferenceIsNotRescaled() {
        var w = StageMappingWatch()
        for _ in 0..<8 { XCTAssertNil(record(&w, dx: 0.75)) }  // 0.25 per degree: 1.25x
    }

    func testLostTrackingMovesAreIgnored() {
        var w = StageMappingWatch()
        for _ in 0..<6 { XCTAssertNil(record(&w, dx: -0.6, lost: true)) }
        // Nothing was kept: two real opposite moves are still too few to flip.
        XCTAssertNil(record(&w, dx: -0.6))
        XCTAssertNil(record(&w, dx: -0.6))
    }
}
