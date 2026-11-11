import XCTest

@testable import AuraFarm

final class MovementIndicatorsTests: XCTestCase {
    /// Short side 100 px, so speed fractions read as px / 100.
    private let size = CGSize(width: 200, height: 100)

    private func feed(
        _ indicators: inout MovementIndicators, shake: CGPoint?, at seconds: Double = 0,
        anchorOffset: CGPoint? = nil, position: CGPoint = .zero, isLost: Bool = false,
        event: HopOdometer.Event = .none
    ) {
        indicators.update(
            shake: shake, anchorOffset: anchorOffset, positionFrames: position, isLost: isLost,
            event: event, frameSize: size, seconds: seconds, hopFraction: 0.3)
    }

    func testStatuses() {
        var indicators = MovementIndicators()
        XCTAssertEqual(indicators.status, .starting)
        feed(&indicators, shake: nil)
        XCTAssertEqual(indicators.status, .starting, "a nil shake does not end starting")
        feed(&indicators, shake: CGPoint(x: 1, y: 0))
        XCTAssertEqual(indicators.status, .tracking)
        feed(&indicators, shake: CGPoint(x: 60, y: 0))
        feed(&indicators, shake: CGPoint(x: 60, y: 0))
        feed(&indicators, shake: CGPoint(x: 60, y: 0))
        XCTAssertEqual(indicators.status, .tooFast)
        feed(&indicators, shake: CGPoint(x: 1, y: 0), isLost: true)
        XCTAssertEqual(indicators.status, .lost, "lost wins over too fast")
    }

    func testSpeedZoneBoundariesAndAveraging() {
        var indicators = MovementIndicators(thresholds: .init(speedWindow: 1))
        feed(&indicators, shake: CGPoint(x: 7.9, y: 0))
        XCTAssertEqual(indicators.speedZone, .comfortable)
        feed(&indicators, shake: CGPoint(x: 8, y: 0))
        XCTAssertEqual(indicators.speedZone, .fast)
        feed(&indicators, shake: CGPoint(x: 17.9, y: 0))
        XCTAssertEqual(indicators.speedZone, .fast)
        feed(&indicators, shake: CGPoint(x: 18, y: 0))
        XCTAssertEqual(indicators.speedZone, .tooFast)

        var averaged = MovementIndicators()
        feed(&averaged, shake: CGPoint(x: 30, y: 0))
        feed(&averaged, shake: nil)
        feed(&averaged, shake: CGPoint(x: 0, y: 6))
        XCTAssertEqual(averaged.speedFraction, (0.3 + 0 + 0.06) / 3, accuracy: 0.0001)
        feed(&averaged, shake: CGPoint(x: 0, y: 0))
        XCTAssertEqual(averaged.speedFraction, 0.02, accuracy: 0.0001, "the window slides")
    }

    func testHopProgressClampsAndResetsOnAHop() {
        var indicators = MovementIndicators()
        feed(&indicators, shake: .zero, anchorOffset: nil)
        XCTAssertEqual(indicators.hopProgress, 0)
        feed(&indicators, shake: .zero, anchorOffset: CGPoint(x: 15, y: 0))
        XCTAssertEqual(indicators.hopProgress, 0.5, accuracy: 0.0001)
        feed(&indicators, shake: .zero, anchorOffset: CGPoint(x: 0, y: -90))
        XCTAssertEqual(indicators.hopProgress, 1)
        feed(&indicators, shake: .zero, anchorOffset: CGPoint(x: 30, y: 0), event: .hop)
        XCTAssertEqual(indicators.hopProgress, 0)
    }

    func testStillnessTimerGrowsAndResets() {
        var indicators = MovementIndicators()
        feed(&indicators, shake: CGPoint(x: 0.5, y: 0), at: 10)
        XCTAssertEqual(indicators.stillSeconds, 0, "the first frame has no elapsed time")
        feed(&indicators, shake: CGPoint(x: 0.5, y: 0), at: 10.4)
        feed(&indicators, shake: CGPoint(x: 0, y: 1), at: 10.9)
        XCTAssertEqual(indicators.stillSeconds, 0.9, accuracy: 0.0001)
        feed(&indicators, shake: CGPoint(x: 5, y: 0), at: 11.0)
        XCTAssertEqual(indicators.stillSeconds, 0)
        feed(&indicators, shake: CGPoint(x: 0, y: 0), at: 11.5)
        feed(&indicators, shake: nil, at: 12)
        XCTAssertEqual(indicators.stillSeconds, 0, "no reading is not evidence of stillness")
    }

    func testOffStartAndHome() {
        var indicators = MovementIndicators()
        XCTAssertNil(indicators.offStartFrames)
        XCTAssertFalse(indicators.isHome)
        feed(&indicators, shake: .zero, position: CGPoint(x: 1, y: 1))
        indicators.markStart(at: CGPoint(x: 1, y: 1))
        XCTAssertEqual(indicators.offStartFrames ?? -1, 0, accuracy: 0.0001)
        XCTAssertTrue(indicators.isHome)
        feed(&indicators, shake: .zero, position: CGPoint(x: 4, y: 5))
        XCTAssertEqual(indicators.offStartFrames ?? -1, 5, accuracy: 0.0001)
        XCTAssertFalse(indicators.isHome)
        feed(&indicators, shake: .zero, position: CGPoint(x: 1.2, y: 1))
        XCTAssertTrue(indicators.isHome)
        feed(&indicators, shake: .zero, position: CGPoint(x: 1.3, y: 1))
        XCTAssertFalse(indicators.isHome, "just past the 0.25 frame zone")
    }

    func testClearStartAndReset() {
        var indicators = MovementIndicators()
        feed(&indicators, shake: CGPoint(x: 30, y: 0), at: 1, position: CGPoint(x: 1, y: 0))
        indicators.markStart(at: .zero)
        indicators.clearStart()
        XCTAssertNil(indicators.startPosition)
        XCTAssertNil(indicators.offStartFrames)

        indicators.markStart(at: .zero)
        indicators.reset()
        XCTAssertEqual(indicators.status, .starting)
        XCTAssertEqual(indicators.speedFraction, 0)
        XCTAssertNil(indicators.startPosition)
        XCTAssertEqual(indicators.stillSeconds, 0)
    }

    func testStatusNamesForTheCSV() {
        XCTAssertEqual(MovementIndicators.Status.tooFast.csvName, "too_fast")
        XCTAssertEqual(MovementIndicators.Status.starting.csvName, "starting")
    }
}
