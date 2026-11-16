import XCTest

@testable import AuraFarm

/// Phase 2k part C: the two-sided focus dial. Passing the peak is what tells the side.
final class FocusDialTests: XCTestCase {
    private var seconds = 0.0

    private func feed(_ dial: inout FocusDial, _ values: [Double]) -> FocusDialReading {
        var last = dial.update(value: values[0], seconds: seconds)
        for value in values.dropFirst() {
            seconds += 0.1
            last = dial.update(value: value, seconds: seconds)
        }
        return last
    }

    private func setupDial() -> FocusDial {
        FocusDial(target: nil, goodShare: 0.9, raisesTarget: true)
    }

    func testRisingToTheTargetThenPastByThirtyPercentIsPastAtAboutPlusThirtyPercent() {
        var dial = setupDial()
        let rising = feed(&dial, [0.2, 0.5, 0.8, 1.0])
        XCTAssertEqual(rising.side, .approaching)
        XCTAssertTrue(rising.isGreen)
        let past = feed(&dial, [0.85, 0.7])
        XCTAssertEqual(past.side, .past)
        XCTAssertEqual(past.offset, 0.3, accuracy: 0.01)
        XCTAssertEqual(past.message, "Too far. Turn back slowly")
    }

    func testTurningBackBringsTheOffsetToZeroAndTheGreenZoneShows() {
        var dial = setupDial()
        _ = feed(&dial, [0.2, 0.6, 1.0, 0.7])
        let back = feed(&dial, [0.85, 0.97, 1.0])
        XCTAssertEqual(back.side, .past)
        XCTAssertEqual(back.offset, 0, accuracy: 0.01)
        XCTAssertTrue(back.isGreen)
        XCTAssertEqual(back.message, "Sharp ✓")
    }

    func testOvershootingAgainFlipsTheSideBack() {
        var dial = setupDial()
        _ = feed(&dial, [0.2, 0.6, 1.0, 0.7, 0.85, 1.0])
        let again = feed(&dial, [0.9, 0.7])
        XCTAssertEqual(again.side, .approaching)
        XCTAssertEqual(again.offset, -0.3, accuracy: 0.01)
    }

    func testAnUnknownStartThenFallingIsTheWrongWay() {
        var dial = FocusDial(target: 1, goodShare: 0.8, startsUnknown: true)
        let start = feed(&dial, [0.6])
        XCTAssertEqual(start.side, .unknown)
        XCTAssertFalse(start.isWrongWay)
        let falling = feed(&dial, [0.55, 0.5])
        XCTAssertTrue(falling.isWrongWay)
        XCTAssertEqual(falling.message, "Wrong way. Turn the other way")
        XCTAssertEqual(falling.csvSide, "wrong_way")
        XCTAssertGreaterThan(falling.offset, 0, "the needle is on the far side")
        let rising = feed(&dial, [0.6, 0.7])
        XCTAssertEqual(rising.side, .approaching)
        XCTAssertFalse(rising.isWrongWay)
    }

    func testSetupRaisesTheTargetOnANewPeak() {
        var dial = setupDial()
        _ = feed(&dial, [0.3, 0.5])
        let raised = feed(&dial, [0.8])
        XCTAssertEqual(try XCTUnwrap(dial.target), 0.8, accuracy: 1e-9)
        XCTAssertEqual(raised.offset, 0, accuracy: 1e-9)
    }

    func testAlmostThereShowsJustOutsideTheGreenZone() {
        var dial = FocusDial(target: 1, goodShare: 0.8)
        XCTAssertEqual(feed(&dial, [0.75]).message, "Almost there. Slowly")
        XCTAssertEqual(feed(&dial, [0.2]).message, "Keep turning slowly")
    }
}
