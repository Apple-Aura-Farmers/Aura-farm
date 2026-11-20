import XCTest

@testable import AuraFarm

/// Phase 2h part E1: the run monitor pauses slowly and resumes only when the picture is back.
final class RunMonitorTests: XCTestCase {
    private var monitor = RunMonitor()
    private var seconds = 0.0
    private let confirmed = FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 300)

    private func reading(
        shift: Double = 0, radiusChange: Double = 0, clipped: Bool = false, found: Bool = true
    ) -> AlignmentReading {
        var reading = AlignmentReading()
        reading.found = found
        reading.circle = FieldCircle(
            centre: CGPoint(x: 640 + shift * 300, y: 360), radius: 300 * (1 + radiusChange))
        reading.roundness = 0.95
        if clipped { reading.clippedSides = [.right] }
        return reading
    }

    @discardableResult
    private func feed(
        alignment: AlignmentReading? = nil, focus: Double? = nil, sharpness: Double? = nil,
        viewClass: ViewClass = .sample, tracking: TrackingState = .tracking, still: Bool = true,
        for duration: Double
    ) -> RunMonitorState {
        var state = monitor.state
        for _ in 0..<Int((duration * 10).rounded()) {
            seconds += 0.1
            state = monitor.update(
                alignment: alignment, confirmedCircle: confirmed, focusIndex: focus,
                boxSharpness: sharpness, viewClass: viewClass, tracking: tracking, isStill: still,
                seconds: seconds)
        }
        return state
    }

    private func withBaseline() {
        monitor.setFocusBaseline(1.0)
    }

    func testAFocusDipBelowSixtyPercentForTwoSecondsDoesNotPauseButTwoAndAHalfDoes() {
        withBaseline()
        XCTAssertEqual(feed(focus: 0.5, for: 2.0), .ok, "2.0 s")
        XCTAssertEqual(feed(focus: 1.0, for: 0.5), .ok, "a good reading clears the count")
        XCTAssertEqual(feed(focus: 0.5, for: 2.5), .ok, "readings spanning 2.4 s")
        XCTAssertEqual(feed(focus: 0.5, for: 0.1), .pausedFocus, "spanning 2.5 s")
    }

    func testItResumesAtEightyPercentForOneSecond() {
        withBaseline()
        feed(focus: 0.5, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        XCTAssertEqual(feed(focus: 0.7, for: 3), .pausedFocus, "70% is not enough")
        XCTAssertEqual(feed(focus: 0.85, for: 1.0), .pausedFocus, "spanning 0.9 s")
        XCTAssertEqual(feed(focus: 0.85, for: 0.1), .ok, "spanning 1.0 s at 85%")
    }

    func testReadingsOnBlankOrBlurryViewClassesAreIgnored() {
        withBaseline()
        for viewClass in [ViewClass.blank, .blurry, .dark] {
            XCTAssertEqual(feed(focus: 0.1, viewClass: viewClass, for: 10), .ok, "\(viewClass)")
        }
        XCTAssertEqual(feed(focus: 0.1, tracking: .paused, for: 10), .ok)
        // An ignored reading in the middle clears the count: 2 s + gap + 2 s is not 4 s.
        feed(focus: 0.1, for: 2.0)
        feed(focus: 0.1, viewClass: .blank, for: 0.1)
        XCTAssertEqual(feed(focus: 0.1, for: 2.0), .ok)
    }

    func testACentreShiftOfPointTwoFiveRadiiForThreeSecondsPausesAndBackWithinPointZeroSixResumes() {
        let shifted = reading(shift: 0.25)
        XCTAssertEqual(feed(alignment: shifted, for: 3.0), .ok, "spanning 2.9 s")
        XCTAssertEqual(feed(alignment: shifted, for: 0.1), .pausedAlignment, "spanning 3.0 s")
        XCTAssertEqual(monitor.circleShift ?? 0, 0.25, accuracy: 1e-6)
        // 0.08 is better but not back (limit 0.06).
        XCTAssertEqual(feed(alignment: reading(shift: 0.08), for: 3), .pausedAlignment)
        XCTAssertEqual(feed(alignment: reading(shift: 0.05), for: 1.0), .pausedAlignment)
        XCTAssertEqual(feed(alignment: reading(shift: 0.05), for: 0.1), .ok)
    }

    func testAShiftHeldOnlyTwoAndAHalfSecondsDoesNotPause() {
        XCTAssertEqual(feed(alignment: reading(shift: 0.25), for: 2.5), .ok)
        // 0.15 is under the new 0.18 limit however long.
        XCTAssertEqual(feed(alignment: reading(shift: 0.15), for: 6), .ok)
    }

    func testARadiusChangeAClippedCircleOrNoCircleAlsoPauses() {
        XCTAssertEqual(feed(alignment: reading(radiusChange: 0.2), for: 3.1), .pausedAlignment)
        monitor.reset()
        XCTAssertEqual(feed(alignment: reading(clipped: true), for: 3.1), .pausedAlignment)
        monitor.reset()
        XCTAssertEqual(feed(alignment: reading(found: false), for: 3.1), .pausedAlignment)
        monitor.reset()
        XCTAssertEqual(feed(alignment: reading(shift: 0.1, radiusChange: 0.08), for: 5), .ok)
    }

    func testAlignmentWinsOverFocus() {
        withBaseline()
        feed(focus: 0.4, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        XCTAssertEqual(feed(alignment: reading(shift: 0.3), focus: 0.4, for: 3.1), .pausedAlignment)
        // Focus is not judged while alignment is paused, and starts counting again afterwards.
        XCTAssertEqual(feed(alignment: reading(), focus: 1.0, for: 1.1), .ok)
    }

    func testWithoutASetupBaselineTheMedianOfTheFirstThreeSecondsIsUsed() {
        XCTAssertNil(monitor.focusBaseline)
        feed(focus: 0.8, for: 1.4)
        feed(focus: 1.0, for: 1.8)
        XCTAssertEqual(monitor.focusBaseline ?? 0, 1.0, accuracy: 1e-9)
        feed(focus: 0.5, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        monitor.reset()
        XCTAssertEqual(monitor.focusBaseline ?? 0, 1.0, accuracy: 1e-9, "reset keeps the baseline")
    }

    func testPauseReasonsMapToTheRoute() {
        XCTAssertNil(RunMonitorState.ok.pauseReason)
        XCTAssertEqual(RunMonitorState.pausedAlignment.pauseReason, .alignment)
        XCTAssertEqual(RunMonitorState.pausedFocus.pauseReason, .focus)
    }

    // MARK: Phase 2i: only still readings count

    func testAMovingDipNeverPauses() {
        withBaseline()
        XCTAssertEqual(feed(focus: 0.3, still: false, for: 10), .ok)
        XCTAssertFalse(monitor.isFocusLow)
    }

    func testAStillDipPausesAndLowMovingLowRestartsTheCount() {
        withBaseline()
        XCTAssertEqual(feed(focus: 0.5, for: 2.6), .pausedFocus)
        monitor.reset()
        feed(focus: 0.5, for: 2.0)
        feed(focus: 0.5, still: false, for: 0.1)
        XCTAssertEqual(feed(focus: 0.5, for: 2.0), .ok, "a moving reading restarted the count")
        XCTAssertEqual(feed(focus: 0.5, for: 0.6), .pausedFocus)
    }

    func testAResumeNeedsStillGoodReadings() {
        withBaseline()
        feed(focus: 0.5, for: 2.6)
        XCTAssertEqual(feed(focus: 1.0, still: false, for: 5), .pausedFocus)
        XCTAssertEqual(feed(focus: 1.0, for: 1.1), .ok)
    }

    func testTheBaselineIgnoresMovingReadings() {
        feed(focus: 0.2, still: false, for: 5)
        XCTAssertNil(monitor.focusBaseline)
        feed(focus: 1.0, for: 3.2)
        XCTAssertEqual(monitor.focusBaseline ?? 0, 1.0, accuracy: 1e-9)
    }

    func testFocusLowIsTheLatestStillEligibleReadingUnderSixtyPercent() {
        XCTAssertFalse(monitor.isFocusLow, "no baseline")
        withBaseline()
        feed(focus: 0.5, for: 0.1)
        XCTAssertTrue(monitor.isFocusLow)
        feed(focus: 0.5, still: false, for: 0.1)
        XCTAssertFalse(monitor.isFocusLow, "the latest reading was moving")
        feed(focus: 0.5, for: 0.1)
        feed(focus: 0.5, viewClass: .blank, for: 0.1)
        XCTAssertFalse(monitor.isFocusLow, "not eligible")
        feed(focus: 0.5, for: 0.1)
        XCTAssertTrue(monitor.isFocusLow)
        XCTAssertEqual(feed(alignment: reading(shift: 0.3), focus: 0.5, for: 3.1), .pausedAlignment)
        XCTAssertFalse(monitor.isFocusLow, "alignment wins")
        feed(focus: 1.0, for: 0.1)
    }

    // MARK: Phase 2j part B: detail lost while still

    func testDetailLostWhileStillPausesForFocusAtTwoAndAHalfSeconds() {
        withBaseline()
        feed(focus: 1.0, sharpness: 400, for: 1.0)
        XCTAssertEqual(feed(sharpness: 60, tracking: .paused, for: 2.5), .ok, "spanning 2.4 s")
        XCTAssertTrue(monitor.isStillOnset)
        XCTAssertTrue(monitor.isFocusLow)
        XCTAssertEqual(feed(sharpness: 60, tracking: .paused, for: 0.1), .pausedFocus)
    }

    func testBlankOrBlurryWithTrackingOnAlsoCountsButDarkNeverDoes() {
        withBaseline()
        feed(focus: 1.0, sharpness: 400, for: 1.0)
        XCTAssertEqual(feed(sharpness: 60, viewClass: .blurry, for: 2.6), .pausedFocus)
        monitor.reset()
        feed(focus: 1.0, sharpness: 400, for: 1.0)
        XCTAssertEqual(feed(sharpness: 5, viewClass: .dark, for: 6), .ok)
        XCTAssertFalse(monitor.isStillOnset)
    }

    func testAMovingLookbackNeverPausesForFocus() {
        withBaseline()
        feed(focus: 1.0, sharpness: 400, still: false, for: 1.0)
        XCTAssertEqual(feed(sharpness: 60, tracking: .paused, for: 5), .ok)
        XCTAssertFalse(monitor.isStillOnset)
    }

    func testAnEmptyLookbackNeverPausesForFocus() {
        withBaseline()
        XCTAssertEqual(feed(sharpness: 60, tracking: .paused, for: 5), .ok)
    }

    func testADipAboveTheDropShareNeverPauses() {
        withBaseline()
        feed(focus: 1.0, sharpness: 140, for: 1.0)
        XCTAssertEqual(feed(sharpness: 110, tracking: .paused, for: 6), .ok)
        XCTAssertFalse(monitor.isFocusLow)
    }

    func testItResumesWhenDetailIsBackAndStillButNotWhileMoving() {
        withBaseline()
        feed(focus: 1.0, sharpness: 400, for: 1.0)
        feed(sharpness: 60, tracking: .paused, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        XCTAssertEqual(feed(focus: 0.9, sharpness: 400, still: false, for: 3), .pausedFocus)
        XCTAssertEqual(feed(focus: 0.9, sharpness: 400, for: 0.9), .pausedFocus, "spanning 0.8 s")
        XCTAssertEqual(feed(focus: 0.9, sharpness: 400, for: 0.2), .ok)
    }

    func testWithoutABaselineAStillOnsetPausesAndDetailPlusStillResumes() {
        feed(focus: 1.0, sharpness: 400, for: 0.6)
        XCTAssertNil(monitor.focusBaseline)
        XCTAssertEqual(feed(sharpness: 60, tracking: .paused, for: 2.6), .pausedFocus)
        XCTAssertEqual(feed(focus: 0.2, sharpness: 400, for: 1.2), .ok)
    }

    // MARK: Two-signal focus pause (Phase 2s-D part C), numbers from the 17 Nov device runs

    func testRunBFalsePauseDoesNotHappenWhenTheFocusIndexIsLowButTheFrameIsSharp() {
        monitor.setFocusBaseline(0.443)
        feed(focus: 0.5, sharpness: 1660, for: 8)
        XCTAssertEqual(feed(focus: 0.24, sharpness: 2105, for: 4), .ok, "sharp: not a focus pause")
        XCTAssertFalse(monitor.isFocusLow)
        XCTAssertEqual(try XCTUnwrap(monitor.sharpnessShare), 1.27, accuracy: 0.05)
    }

    func testRunAPausesAfterTwoAndAHalfSecondsWhenBothSignalsAreLow() {
        monitor.setFocusBaseline(0.222)
        feed(focus: 0.3, sharpness: 2240, for: 8)
        XCTAssertEqual(feed(focus: 0.08, sharpness: 585, for: 2.4), .ok)
        XCTAssertEqual(feed(focus: 0.08, sharpness: 585, for: 0.2), .pausedFocus)
        XCTAssertEqual(monitor.pauseCause, "index_and_sharpness")
        XCTAssertEqual(try XCTUnwrap(monitor.sharpnessShare), 0.26, accuracy: 0.02)
    }

    func testAPauseEndsOnSharpnessAloneAndTheReferenceSurvivesALongPause() {
        monitor.setFocusBaseline(0.222)
        feed(focus: 0.3, sharpness: 2240, for: 8)
        feed(focus: 0.08, sharpness: 585, for: 3)
        XCTAssertEqual(monitor.state, .pausedFocus)
        feed(focus: 0.08, sharpness: 585, for: 60)
        XCTAssertEqual(monitor.state, .pausedFocus, "still blurry: stays paused")
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1600, for: 3), .pausedFocus, "0.71 of the reference")
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1900, for: 0.9), .pausedFocus, "spanning 0.8 s")
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1900, for: 0.2), .ok, "0.85 of the reference")
    }

    func testSharpnessBackAtEightyPercentOfTheReferenceResumes() {
        monitor.setFocusBaseline(0.222)
        feed(focus: 0.3, sharpness: 2240, for: 8)
        feed(focus: 0.08, sharpness: 585, for: 3)
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1900, for: 1.2), .ok)
        XCTAssertEqual(monitor.pauseCause, "")
    }

    func testResumingByHandMeasuresTheBaselineAgain() {
        monitor.setFocusBaseline(0.222)
        feed(focus: 0.3, sharpness: 2240, for: 8)
        feed(focus: 0.08, sharpness: 585, for: 3)
        XCTAssertEqual(monitor.state, .pausedFocus)
        monitor.resumeManually()
        XCTAssertEqual(monitor.state, .ok)
        XCTAssertNil(monitor.focusBaseline)
        feed(focus: 0.4, sharpness: 2000, for: 3.2)
        XCTAssertEqual(try XCTUnwrap(monitor.focusBaseline), 0.4, accuracy: 1e-9)
        monitor.resumeManually()
        XCTAssertEqual(monitor.state, .ok, "nothing to resume from when not paused")
    }

    func testTheFirstFiveSecondsBehaveAsBefore() {
        monitor.setFocusBaseline(1.0)
        XCTAssertEqual(feed(focus: 0.5, sharpness: 2000, for: 2.6), .pausedFocus, "no reference yet")
    }

    func testAlignmentPauseSaysSoInTheCsv() {
        feed(alignment: reading(shift: 0.3), for: 3.1)
        XCTAssertEqual(monitor.state, .pausedAlignment)
        XCTAssertEqual(monitor.pauseCause, "alignment")
    }
}
