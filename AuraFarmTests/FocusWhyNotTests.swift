import XCTest

@testable import AuraFarm

/// Why the focus check had not accepted: setup's guide and the run's pause.
final class FocusWhyNotTests: XCTestCase {
    private var guide = FocusGuide()
    private var seconds = 0.0
    private var reading: FocusReading?

    private func feed(_ values: [Double]) {
        for value in values {
            seconds += 0.1
            reading = guide.update(sharpness: value, seconds: seconds)
        }
    }

    private func ramp(_ from: Double, _ to: Double, _ count: Int) -> [Double] {
        (1...count).map { from + (to - from) * Double($0) / Double(count) }
    }

    private func why(faded: Bool = false, confirm: Bool = false) -> [String] {
        FocusGuide.whyNot(guide, reading: reading, faded: faded, awaitsConfirm: confirm)
    }

    // MARK: Setup

    func testNoReading() {
        XCTAssertEqual(why(), ["no_reading"])
    }

    func testAPeakTooLowAndASweepThatRisesTooLittle() {
        feed([Double](repeating: 30, count: 20))
        XCTAssertEqual(why(), ["peak_too_low"])
        guide.reset()
        feed([Double](repeating: 80, count: 20))
        XCTAssertEqual(why(), ["rise_too_small"])
    }

    func testARealPeakNeverPassed() {
        feed(ramp(50, 500, 40))
        XCTAssertEqual(why(), ["never_passed_peak"])
    }

    func testPassedButBelowNear() {
        feed(ramp(50, 500, 40) + ramp(500, 200, 20))
        XCTAssertEqual(reading?.state, .passedPeak)
        XCTAssertEqual(why(), ["below_near"])
    }

    func testNearButNotSteady() {
        feed(ramp(50, 500, 40) + ramp(500, 200, 20) + ramp(200, 475, 10))
        XCTAssertEqual(reading?.state, .nearPeak)
        XCTAssertEqual(why(), ["not_steady"])
    }

    func testFadedAndNotConfirmedAreAddedAndAFocusedGuideHasNoReasonOfItsOwn() {
        feed(ramp(50, 500, 40) + ramp(500, 200, 20) + ramp(200, 475, 10))
        feed([Double](repeating: 475, count: 30))
        XCTAssertEqual(reading?.state, .focused)
        XCTAssertEqual(why(), [], "empty when the check accepts")
        XCTAssertEqual(why(faded: true, confirm: true), ["faded", "not_confirmed"])
    }

    // MARK: Run

    private func run(
        state: RunMonitorState = .pausedFocus, index: Double? = 0.9, baseline: Double? = 1,
        share: Double? = 0.3, isSharp: Bool = false, view: ViewClass = .sample,
        tracking: TrackingState = .tracking, still: Bool = true
    ) -> [String] {
        RunMonitor.whyNotResumed(
            state: state, index: index, baseline: baseline, sharpnessShare: share, isSharp: isSharp,
            viewClass: view, tracking: tracking, isStill: still)
    }

    func testARunThatIsNotPausedHoldsNothingBack() {
        XCTAssertEqual(run(state: .ok), [])
        XCTAssertEqual(run(state: .pausedAlignment), [])
    }

    func testTheIndexAndTheSharpnessShare() {
        XCTAssertEqual(run(index: nil), ["no_index", "sharpness_below_share"])
        XCTAssertEqual(run(index: 0.5), ["index_below_resume", "sharpness_below_share"])
        // One of the two is enough, then the peak decides.
        XCTAssertEqual(run(index: 0.5, share: 0.9), ["not_near_peak"])
        XCTAssertEqual(run(index: 0.9), ["not_near_peak"])
    }

    func testViewClassTrackingAndMoving() {
        XCTAssertEqual(run(view: .blank), ["view_class"])
        XCTAssertEqual(run(tracking: .paused), ["not_tracking"])
        XCTAssertEqual(run(isSharp: true, still: false), ["moving"])
    }

    func testEverythingMetButNotForLongEnough() {
        XCTAssertEqual(run(isSharp: true), ["not_long_enough"])
    }
}
