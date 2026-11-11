import XCTest

@testable import AuraFarm

final class AnalysisLoadTests: XCTestCase {
    func testFallingBehind() {
        let limits = AnalysisLoadThresholds()
        XCTAssertFalse(limits.isFallingBehind(milliseconds: 42, framesPerSecond: 9.8))
        XCTAssertTrue(limits.isFallingBehind(milliseconds: 100.1, framesPerSecond: 9.8))
        XCTAssertFalse(limits.isFallingBehind(milliseconds: 100, framesPerSecond: 9.8))
        XCTAssertTrue(limits.isFallingBehind(milliseconds: 42, framesPerSecond: 4.9))
        XCTAssertFalse(limits.isFallingBehind(milliseconds: 42, framesPerSecond: 5))
    }

    func testAnUnknownRateIsNotAProblem() {
        XCTAssertFalse(AnalysisLoadThresholds().isFallingBehind(milliseconds: 10, framesPerSecond: 0))
    }
}
