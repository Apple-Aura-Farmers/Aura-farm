import XCTest

@testable import AuraFarm

final class CountBandsTests: XCTestCase {
    private let bands = CountBands()

    func testCommonBoundaries() {
        XCTAssertEqual(bands.band(perFrame: 0.29, abundance: .common), .low)
        XCTAssertEqual(bands.band(perFrame: 0.3, abundance: .common), .typical)
        XCTAssertEqual(bands.band(perFrame: 2, abundance: .common), .typical)
        XCTAssertEqual(bands.band(perFrame: 2.01, abundance: .common), .high)
    }

    func testModerateBoundaries() {
        XCTAssertEqual(bands.band(perFrame: 0.09, abundance: .moderate), .low)
        XCTAssertEqual(bands.band(perFrame: 0.1, abundance: .moderate), .typical)
        XCTAssertEqual(bands.band(perFrame: 1, abundance: .moderate), .typical)
        XCTAssertEqual(bands.band(perFrame: 1.01, abundance: .moderate), .high)
    }

    func testScarceBoundariesNeverLow() {
        XCTAssertEqual(bands.band(perFrame: 0, abundance: .scarce), .typical)
        XCTAssertEqual(bands.band(perFrame: 0.3, abundance: .scarce), .typical)
        XCTAssertEqual(bands.band(perFrame: 0.31, abundance: .scarce), .high)
    }
}
