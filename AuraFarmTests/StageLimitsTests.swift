import XCTest

@testable import AuraFarm

final class StageLimitsTests: XCTestCase {
    func testDefaultsAreTheWholeTurn() {
        let limits = StageLimits()
        XCTAssertEqual(limits.range(of: .x), 0...180)
        XCTAssertEqual(limits.range(of: .y), 0...180)
    }

    func testClampKeepsAnAngleInsideItsServosRange() {
        let limits = StageLimits(xMin: 10, xMax: 170, yMin: 20, yMax: 160)
        XCTAssertEqual(limits.clamp(5, .x), 10)
        XCTAssertEqual(limits.clamp(175, .x), 170)
        XCTAssertEqual(limits.clamp(90, .x), 90)
        XCTAssertEqual(limits.clamp(5, .y), 20)
        XCTAssertEqual(limits.clamp(175, .y), 160)
    }

    func testIsAtEnd() {
        let limits = StageLimits(xMin: 10, xMax: 170)
        XCTAssertEqual(limits.isAtEnd(.x, 10), .min)
        XCTAssertEqual(limits.isAtEnd(.x, 170), .max)
        XCTAssertNil(limits.isAtEnd(.x, 90))
        XCTAssertEqual(limits.isAtEnd(.y, 0), .min)
        XCTAssertEqual(limits.isAtEnd(.y, 180), .max)
    }

    func testARefusalNarrowsOnlyThatAxis() {
        var limits = StageLimits()
        limits.merge(refusal: "LIMIT 10-170", axis: .y)
        XCTAssertEqual(limits.range(of: .y), 10...170)
        XCTAssertEqual(limits.range(of: .x), 0...180)
    }

    func testNonsenseIsIgnored() {
        var limits = StageLimits()
        for text in [
            "LIMIT 170-10", "LIMIT 90-90", "LIMIT 0-181", "LIMIT a-b", "LIMIT 10", "LIMIT", "",
            "BUSY 10-170", "LIMIT 10-170 extra", "LIMIT -5-170",
        ] {
            limits.merge(refusal: text, axis: .x)
            XCTAssertEqual(limits, StageLimits(), text)
        }
    }
}
