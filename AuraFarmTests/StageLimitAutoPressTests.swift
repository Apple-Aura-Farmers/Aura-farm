import XCTest

@testable import AuraFarm

final class StageLimitAutoPressTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    private func update(
        _ p: inout StageLimitAutoPress, at seconds: Double, moved: Bool = false
    ) -> Bool {
        p.update(
            now: t0.addingTimeInterval(seconds), atLimit: true, lastSettledAt: t0,
            movedSinceLastPress: moved)
    }

    func testWaitsForSettle() {
        var p = StageLimitAutoPress()
        XCTAssertFalse(update(&p, at: 0.5))
        XCTAssertTrue(update(&p, at: 1.0))
    }

    func testNotAtLimitNeverPresses() {
        var p = StageLimitAutoPress()
        XCTAssertFalse(
            p.update(
                now: t0.addingTimeInterval(5), atLimit: false, lastSettledAt: t0,
                movedSinceLastPress: false))
    }

    func testNoSecondPressWithinRetry() {
        var p = StageLimitAutoPress()
        XCTAssertTrue(update(&p, at: 1.0))
        XCTAssertFalse(update(&p, at: 3.0))
        XCTAssertFalse(update(&p, at: 6.9))
    }

    func testRetryAfterRetrySeconds() {
        var p = StageLimitAutoPress()
        XCTAssertTrue(update(&p, at: 1.0))
        XCTAssertTrue(update(&p, at: 7.0))
    }

    func testMoveStartsNewEpisode() {
        var p = StageLimitAutoPress()
        XCTAssertTrue(update(&p, at: 1.0))
        XCTAssertFalse(update(&p, at: 2.0))
        XCTAssertTrue(update(&p, at: 2.0, moved: true))
    }
}
