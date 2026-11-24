import XCTest

@testable import AuraFarm

final class OperatorSetupScreensTests: XCTestCase {
    func testAlignState() {
        var reading = AlignmentReading()
        XCTAssertEqual(OperatorAlignState(reading: reading, passed: false), .outOfView)
        reading.found = true
        XCTAssertEqual(OperatorAlignState(reading: reading, passed: false), .adjusting)
        reading.clippedSides = [.left]
        XCTAssertEqual(OperatorAlignState(reading: reading, passed: false), .outOfView)
        XCTAssertEqual(OperatorAlignState(reading: reading, passed: true), .good)
    }

    func testFocusGaugeTones() {
        func reading(_ state: FocusGuideState) -> FocusReading {
            .init(state: state, current: 1, peak: 1, level: 0.9)
        }
        XCTAssertEqual(OperatorFocusGauge(reading: reading(.turnOneWay), dial: nil).tone, .searching)
        XCTAssertEqual(OperatorFocusGauge(reading: reading(.needsSample), dial: nil).tone, .needsSample)
        XCTAssertEqual(OperatorFocusGauge(reading: reading(.nearPeak), dial: nil).tone, .almost)
        XCTAssertEqual(OperatorFocusGauge(reading: reading(.passedPeak), dial: nil).tone, .turnBack)
        XCTAssertEqual(OperatorFocusGauge(reading: reading(.focused), dial: nil).tone, .hold)
    }
}
