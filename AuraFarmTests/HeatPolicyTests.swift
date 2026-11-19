import XCTest

@testable import AuraFarm

/// Performance step 3, part A: thermal state to heat mode, with hysteresis.
final class HeatPolicyTests: XCTestCase {
    func testTheMapping() {
        XCTAssertEqual(HeatPolicy.target(for: .nominal), .normal)
        XCTAssertEqual(HeatPolicy.target(for: .fair), .normal)
        XCTAssertEqual(HeatPolicy.target(for: .serious), .coolDown)
        XCTAssertEqual(HeatPolicy.target(for: .critical), .tooHot)
    }

    func testAHotterModeIsTakenAtOnce() {
        var policy = HeatPolicy()
        XCTAssertEqual(policy.update(.fair, seconds: 0), .normal)
        XCTAssertEqual(policy.update(.serious, seconds: 0.1), .coolDown)
        XCTAssertEqual(policy.update(.critical, seconds: 0.2), .tooHot)
    }

    func testACoolerModeNeedsThirtySecondsAtTheCoolerLevel() {
        var policy = HeatPolicy()
        policy.update(.serious, seconds: 0)
        XCTAssertEqual(policy.update(.fair, seconds: 1), .coolDown)
        XCTAssertEqual(policy.update(.fair, seconds: 30.9), .coolDown, "29.9 s")
        XCTAssertEqual(policy.update(.fair, seconds: 31), .normal, "30 s")
    }

    func testABriefCoolDipDoesNotStepDown() {
        var policy = HeatPolicy()
        policy.update(.serious, seconds: 0)
        policy.update(.fair, seconds: 1)
        XCTAssertEqual(policy.update(.fair, seconds: 20), .coolDown)
        policy.update(.serious, seconds: 21)
        // The count starts again from the next cool reading.
        policy.update(.fair, seconds: 22)
        XCTAssertEqual(policy.update(.fair, seconds: 45), .coolDown, "23 s since the dip")
        XCTAssertEqual(policy.update(.fair, seconds: 52), .normal)
    }

    func testCriticalStepsDownOneLevelAtATime() {
        var policy = HeatPolicy()
        policy.update(.critical, seconds: 0)
        policy.update(.fair, seconds: 1)
        XCTAssertEqual(policy.update(.fair, seconds: 31), .coolDown, "one level, not two")
        XCTAssertEqual(policy.update(.fair, seconds: 60), .coolDown, "29 s into the next level")
        XCTAssertEqual(policy.update(.fair, seconds: 61), .normal)
        // Critical to serious, and serious holds.
        policy.update(.critical, seconds: 70)
        policy.update(.serious, seconds: 71)
        XCTAssertEqual(policy.update(.serious, seconds: 101), .coolDown)
        XCTAssertEqual(policy.update(.serious, seconds: 200), .coolDown)
    }

    func testSecondsInEachModeAreCounted() {
        var policy = HeatPolicy()
        for step in 0...10 { policy.update(.nominal, seconds: Double(step) * 0.5) }
        for step in 11...20 { policy.update(.serious, seconds: Double(step) * 0.5) }
        XCTAssertEqual(policy.secondsByMode[.normal] ?? 0, 5, accuracy: 0.51)
        XCTAssertEqual(policy.secondsByMode[.coolDown] ?? 0, 4.5, accuracy: 0.51)
        policy.resetTimes()
        XCTAssertTrue(policy.secondsByMode.isEmpty)
    }
}
