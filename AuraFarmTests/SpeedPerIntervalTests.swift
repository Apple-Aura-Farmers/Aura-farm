import XCTest

@testable import AuraFarm

/// Speed is shift per 0.1 s, so a dropped frame does not read as a faster hand.
final class SpeedPerIntervalTests: XCTestCase {
    /// A steady 20 px shift per 0.1 s on a 200 px reference, fed at the given gap.
    private func speed(gap: Double, shift: Double, readings: Int = 6) -> Double {
        var indicators = MovementIndicators(thresholds: .init(speedWindow: 1))
        var seconds = 10.0
        for _ in 0..<readings {
            seconds += gap
            indicators.update(
                shake: CGPoint(x: shift, y: 0), anchorOffset: nil, positionFields: .zero,
                isLost: false, event: .none, referenceSide: 200, seconds: seconds,
                hopDistance: 100)
        }
        return indicators.speedFraction
    }

    func testTheSameMotionAtADifferentGapGivesTheSameSpeed() {
        let steady = speed(gap: 0.10, shift: 20)
        // The same hand speed over 0.17 s moves 34 px between frames.
        let dropped = speed(gap: 0.17, shift: 34)
        XCTAssertEqual(steady, 0.1, accuracy: 1e-9)
        XCTAssertEqual(dropped, steady, accuracy: 1e-9)
    }

    func testTheFirstReadingUsesTheReferenceInterval() {
        var indicators = MovementIndicators(thresholds: .init(speedWindow: 1))
        indicators.update(
            shake: CGPoint(x: 20, y: 0), anchorOffset: nil, positionFields: .zero, isLost: false,
            event: .none, referenceSide: 200, seconds: 123.456, hopDistance: 100)
        XCTAssertEqual(indicators.speedFraction, 0.1, accuracy: 1e-9)
        XCTAssertNil(indicators.frameGap)
    }

    func testTheGapIsClampedToHalfAndThreeTimesTheReference() {
        // 0.01 s is clamped to 0.05: 10 px over a "0.05 s" gap reads as 20 px per 0.1 s.
        XCTAssertEqual(speed(gap: 0.01, shift: 10), 0.1, accuracy: 1e-9)
        // 1.0 s is clamped to 0.30: 60 px over a "0.30 s" gap reads as 20 px per 0.1 s.
        XCTAssertEqual(speed(gap: 1.0, shift: 60), 0.1, accuracy: 1e-9)
    }

    func testTheRawGapIsKeptForTheCsv() {
        var indicators = MovementIndicators()
        for seconds in [1.0, 1.17] {
            indicators.update(
                shake: .zero, anchorOffset: nil, positionFields: .zero, isLost: false, event: .none,
                referenceSide: 200, seconds: seconds, hopDistance: 100)
        }
        XCTAssertEqual(indicators.frameGap ?? 0, 0.17, accuracy: 1e-9)
    }

    func testTheSpeedThresholdsKeepTheirValues() {
        let thresholds = MovementIndicatorThresholds()
        XCTAssertEqual(thresholds.comfortableSpeedFraction, 0.08)
        XCTAssertEqual(thresholds.tooFastSpeedFraction, 0.18)
        XCTAssertEqual(thresholds.referenceIntervalSeconds, 0.1)
        XCTAssertEqual(BriefTouchThresholds().maxTouchSpeedFraction, 0.10)
        XCTAssertEqual(LiveCountThresholds().countMaxSpeedFraction, 0.15)
    }
}
