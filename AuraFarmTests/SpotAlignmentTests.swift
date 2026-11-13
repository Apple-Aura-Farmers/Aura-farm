import XCTest

@testable import AuraFarm

final class SpotAlignmentTests: XCTestCase {
    private func reading(
        _ x: Double, _ y: Double = 0, at seconds: Double = 0, still: Bool = false,
        speed: Double = 0.05, viewClass: ViewClass = .sample, tracking: TrackingState = .tracking
    ) -> GuideReading {
        GuideReading(
            seconds: seconds, position: CGPoint(x: x, y: y), tracking: tracking, unconfirmedGaps: 0,
            viewClass: viewClass, speedFraction: speed, isStill: still)
    }

    private func aimed(at x: Double = 2, holds: Bool = true) -> SpotAlignment {
        var alignment = SpotAlignment()
        alignment.setTarget(CGPoint(x: x, y: 0), from: .zero, holds: holds)
        return alignment
    }

    func testMoveAndFarAway() {
        var alignment = aimed(at: 1)
        XCTAssertEqual(alignment.update(reading(0.2)), .move(toward: CGPoint(x: 0.8, y: 0)))
        var far = aimed(at: 5)
        XCTAssertEqual(far.update(reading(0)), .farAway(direction: CGPoint(x: 1, y: 0)))
    }

    func testAlignedWhenOnTargetButNotStill() {
        var alignment = aimed()
        XCTAssertEqual(alignment.update(reading(1.9)), .aligned)
    }

    func testHoldingCountsUpAndCapturesExactlyOnce() {
        var alignment = aimed()
        XCTAssertEqual(alignment.update(reading(2, at: 0, still: true)), .holding(progress: 0))
        XCTAssertEqual(alignment.update(reading(2, at: 0.5, still: true)), .holding(progress: 0.5))
        XCTAssertEqual(alignment.update(reading(2, at: 1.0, still: true)), .captured)
        XCTAssertEqual(alignment.update(reading(2, at: 1.1, still: true)), .aligned)
        XCTAssertEqual(alignment.update(reading(2, at: 3, still: true)), .aligned)
        alignment.setTarget(CGPoint(x: 2, y: 0), from: .zero)
        XCTAssertEqual(alignment.update(reading(2, at: 4, still: true)), .holding(progress: 0))
    }

    func testMovingOrLeavingTheToleranceResetsTheHold() {
        var alignment = aimed()
        _ = alignment.update(reading(2, at: 0, still: true))
        _ = alignment.update(reading(2, at: 0.6, still: true))
        XCTAssertEqual(alignment.update(reading(2, at: 0.7, still: false)), .aligned)
        XCTAssertEqual(alignment.update(reading(2, at: 0.8, still: true)), .holding(progress: 0))
        _ = alignment.update(reading(2, at: 1.5, still: true))
        _ = alignment.update(reading(1.5, at: 1.6, still: true))
        XCTAssertEqual(alignment.update(reading(2, at: 1.7, still: true)), .holding(progress: 0))
    }

    func testTooFarWhenPastTheTargetAlongTheTravelDirection() {
        var alignment = aimed()
        XCTAssertEqual(alignment.update(reading(2.5)), .tooFar)
    }

    func testOtherWayWhenTheDistanceGrowsOnTheNearSide() {
        var alignment = aimed(at: 2)
        XCTAssertEqual(alignment.update(reading(1)), .move(toward: CGPoint(x: 1, y: 0)))
        XCTAssertEqual(alignment.update(reading(0.8)), .move(toward: CGPoint(x: 1.2, y: 0)))
        XCTAssertEqual(alignment.update(reading(0.6)), .otherWay, "0.4 further than the least seen")
        XCTAssertEqual(alignment.update(reading(1.5)), .move(toward: CGPoint(x: 0.5, y: 0)))
    }

    func testTooFarAndOtherWayAreToldApartBySide() {
        var past = aimed(at: 1)
        _ = past.update(reading(0.9))
        XCTAssertEqual(past.update(reading(1.4)), .tooFar)
        var behind = aimed(at: 1)
        _ = behind.update(reading(0.6))
        XCTAssertEqual(behind.update(reading(0.2)), .otherWay)
    }

    func testPriorityRefocusThenSlowDownThenTheRest() {
        var alignment = aimed()
        for index in 0..<2 {
            _ = alignment.update(reading(2.6, at: Double(index) * 0.4, viewClass: .blurry))
        }
        // Blurry for `refocusSeconds` beats slow down, too far and holding.
        XCTAssertEqual(
            alignment.update(reading(2.6, at: 1.0, speed: 0.5, viewClass: .blurry)), .refocus)
        XCTAssertEqual(alignment.update(reading(2.6, speed: 0.5)), .slowDown)
        XCTAssertEqual(alignment.update(reading(2.6, tracking: .lost)), .slowDown)
        XCTAssertEqual(alignment.update(reading(2.6)), .tooFar)
    }

    func testABlurryStretchShorterThanTheRefocusTimeIsNotRefocus() {
        var alignment = aimed()
        for index in 0..<8 {
            let instruction = alignment.update(reading(1.0, at: Double(index) * 0.1, viewClass: .blurry))
            XCTAssertNotEqual(instruction, .refocus)
        }
        XCTAssertNil(alignment.warning(reading(1.0, at: 0.9, viewClass: .blurry), allowsRefocus: false))
    }

    func testATargetToPassThroughIsNeverCaptured() {
        var alignment = aimed(holds: false)
        XCTAssertEqual(alignment.update(reading(2, at: 0, still: true)), .aligned)
        XCTAssertTrue(alignment.isAtTarget)
        XCTAssertEqual(alignment.update(reading(2, at: 5, still: true)), .aligned)
    }
}
