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

    func testItResumesAtEightyPercentForOneAndAHalfSeconds() {
        withBaseline()
        feed(focus: 0.5, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        XCTAssertEqual(feed(focus: 0.7, for: 3), .pausedFocus, "70% is not enough")
        XCTAssertEqual(feed(focus: 0.85, for: 1.4), .pausedFocus, "spanning 1.3 s")
        XCTAssertEqual(feed(focus: 0.85, for: 0.2), .ok, "spanning 1.5 s at 85%")
    }

    /// A pause for focus with baseline 1.0: still detail readings at `start` begin it by
    /// falling to `low`, so the pause starts with `start` as its index.
    private func pauseAt(_ low: Double) {
        withBaseline()
        feed(focus: 1.0, for: 0.5)
        feed(focus: low, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
    }

    func testANoisyIndexPeakDoesNotKeepASharpViewPaused() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 100, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        feed(focus: 0.728, sharpness: 200, for: 0.7)
        feed(focus: 0.1, sharpness: 120, for: 0.6)
        // 117% of the baseline and as sharp as it has been: the index's own peak is noise.
        XCTAssertEqual(feed(focus: 0.38, sharpness: 200, for: 2.2), .ok)
    }

    func testRun6AViewFarLessSharpThanThePauseHasSeenDoesNotResume() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 300, for: 2.6)
        feed(focus: 0.5, sharpness: 2000, for: 1.0)
        XCTAssertEqual(feed(focus: 0.38, sharpness: 600, for: 5), .pausedFocus)
        XCTAssertFalse(monitor.isSharp)
        XCTAssertEqual(feed(focus: 0.5, sharpness: 1900, for: 2.2), .ok)
    }

    func testASharpnessPeakThatCannotBeReachedAgainIsForgotten() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 300, for: 2.6)
        feed(focus: 0.5, sharpness: 2000, for: 1.0)
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 8), .pausedFocus)
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 5), .ok)
    }

    /// Sharpness from before a gap must not come back as a fresh peak after it.
    private func gapThenLessSharp(
        _ gapSeconds: Double, viewClass: ViewClass = .dark, still: Bool = true
    ) {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 300, for: 2.6)
        feed(focus: 0.5, sharpness: 2000, for: 0.9)
        XCTAssertEqual(monitor.state, .pausedFocus)
        feed(focus: 0.1, sharpness: 2000, viewClass: viewClass, still: still, for: gapSeconds)
        XCTAssertEqual(monitor.state, .pausedFocus)
    }

    func testASharpnessPeakDoesNotComeBackAfterADarkGap() {
        gapThenLessSharp(12)
        feed(focus: 0.4, sharpness: 600, for: 0.3)
        XCTAssertNil(monitor.focusHint)
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 1.5), .ok)
    }

    func testASharpnessPeakDoesNotComeBackAfterAMovingGap() {
        gapThenLessSharp(12, viewClass: .sample, still: false)
        feed(focus: 0.4, sharpness: 600, for: 0.3)
        XCTAssertNil(monitor.focusHint)
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 1.5), .ok)
    }

    func testAGapShorterThanThePeakWindowDoesNotExtendThePeak() {
        gapThenLessSharp(6)
        // The peak is still recent, so it counts, but only until its own ten seconds are over.
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 2.5), .pausedFocus)
        XCTAssertEqual(monitor.focusHint, "Turned past focus: turn back a little")
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 3.6), .ok)
    }

    func testOneSpikeOfSharpnessIsNotAPeak() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 300, for: 2.6)
        feed(focus: 0.1, sharpness: 300, for: 1.0)
        feed(focus: 0.1, sharpness: 9000, for: 0.1)
        XCTAssertEqual(feed(focus: 0.4, sharpness: 600, for: 2.0), .ok)
    }

    func testOneBlurryReadingDoesNotStartTheResumeAgainButManyDo() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, for: 2.6)
        feed(focus: 0.5, for: 1.0)
        feed(focus: 0.5, viewClass: .blurry, for: 0.1)
        XCTAssertEqual(feed(focus: 0.5, for: 0.6), .ok)
        feed(focus: 0.1, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        for _ in 0..<10 {
            feed(focus: 0.5, for: 0.2)
            feed(focus: 0.5, viewClass: .blurry, for: 0.2)
        }
        XCTAssertEqual(monitor.state, .pausedFocus, "half the readings are blurry")
    }

    /// Readings ten times a second with the index measured on every third (the run's own rate).
    @discardableResult
    private func feedSparse(
        focus: Double, sharpness: Double, for duration: Double
    ) -> RunMonitorState {
        for i in 0..<Int((duration * 10).rounded()) where monitor.state == .pausedFocus {
            feed(focus: i % 3 == 0 ? focus : nil, sharpness: sharpness, for: 0.1)
        }
        return monitor.state
    }

    func testAPauseEndsWhenTheIndexIsReadOnlyAFewTimesASecond() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 300, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        XCTAssertEqual(feedSparse(focus: 0.5, sharpness: 2000, for: 1.4), .pausedFocus)
        XCTAssertTrue(monitor.isSharp, "also on the frames between readings")
        XCTAssertEqual(feedSparse(focus: 0.5, sharpness: 2000, for: 0.4), .ok)
    }

    func testAPauseDoesNotEndOnAnIndexReadingThatIsTooOld() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, sharpness: 300, for: 2.6)
        feed(focus: 0.5, sharpness: 2000, for: 0.1)
        XCTAssertEqual(feed(sharpness: 2000, for: 4), .pausedFocus)
        XCTAssertFalse(monitor.isSharp)
    }

    func testALowIndexReadOnlyAFewTimesASecondStillPauses() {
        withBaseline()
        for i in 0..<30 { feed(focus: i % 3 == 0 ? 0.5 : nil, for: 0.1) }
        XCTAssertEqual(monitor.state, .pausedFocus)
    }

    func testABlurryViewIsNeverSharpWhateverItsIndex() {
        monitor.setFocusBaseline(0.324)
        feed(focus: 0.1, for: 2.6)
        XCTAssertEqual(feed(focus: 0.5, viewClass: .blurry, for: 15), .pausedFocus)
        XCTAssertFalse(monitor.isSharp)
    }

    func testTheDialIsGreenExactlyWhenTheMonitorCountsTheViewAsSharp() {
        var dial = FocusDial(target: 1, goodShare: 0.8, startsUnknown: true)
        let indexGreen = dial.update(value: 0.95, seconds: 0)
        XCTAssertTrue(indexGreen.isGreen)
        let blurry = indexGreen.matching(isSharp: false)
        XCTAssertFalse(blurry.isGreen)
        XCTAssertGreaterThan(abs(blurry.offset), blurry.greenHalfWidth)
        XCTAssertEqual(blurry.message, "Not sharp yet. Keep turning slowly")
        let sharp = dial.update(value: 0.3, seconds: 0.1).matching(isSharp: true)
        XCTAssertTrue(sharp.isGreen)
        XCTAssertFalse(sharp.isWrongWay)
        XCTAssertLessThan(abs(sharp.offset), sharp.greenHalfWidth)
        XCTAssertEqual(sharp.message, "Sharp ✓ Hold still")
    }

    func testHintTurnedPastFocusGoesOnceSharpAgain() {
        withBaseline()
        feed(focus: 0.4, sharpness: 300, for: 2.6)
        feed(focus: 0.7, sharpness: 2000, for: 1.0)
        XCTAssertNil(monitor.focusHint)
        feed(focus: 0.5, sharpness: 500, for: 0.5)
        XCTAssertEqual(monitor.focusHint, "Turned past focus: turn back a little")
        feed(focus: 0.9, sharpness: 1900, for: 0.5)
        XCTAssertEqual(monitor.state, .pausedFocus)
        XCTAssertNil(monitor.focusHint, "never beside a green dial")
    }

    func testHintTryTurningTheOtherWay() {
        withBaseline()
        feed(focus: 0.5, for: 2.6)  // starts at 0.5
        feed(focus: 0.3, for: 2.0)
        XCTAssertNil(monitor.focusHint, "under 3 s into the pause")
        feed(focus: 0.3, for: 1.5)
        XCTAssertEqual(monitor.focusHint, "Try turning the other way")
        // A peak above the start takes that hint away.
        feed(focus: 0.9, for: 0.2)
        XCTAssertNotEqual(monitor.focusHint, "Try turning the other way")
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
        XCTAssertEqual(feed(focus: 1.0, for: 1.6), .ok)
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
        XCTAssertEqual(feed(focus: 0.9, sharpness: 400, for: 1.4), .pausedFocus, "spanning 1.3 s")
        XCTAssertEqual(feed(focus: 0.9, sharpness: 400, for: 0.3), .ok)
    }

    func testWithoutABaselineAStillOnsetPausesAndDetailPlusStillResumes() {
        feed(focus: 1.0, sharpness: 400, for: 0.6)
        XCTAssertNil(monitor.focusBaseline)
        XCTAssertEqual(feed(sharpness: 60, tracking: .paused, for: 2.6), .pausedFocus)
        XCTAssertEqual(feed(focus: 0.2, sharpness: 400, for: 1.7), .ok)
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
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1900, for: 1.4), .pausedFocus, "spanning 1.3 s")
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1900, for: 0.3), .ok, "0.85 of the reference")
    }

    func testSharpnessBackAtEightyPercentOfTheReferenceResumes() {
        monitor.setFocusBaseline(0.222)
        feed(focus: 0.3, sharpness: 2240, for: 8)
        feed(focus: 0.08, sharpness: 585, for: 3)
        XCTAssertEqual(feed(focus: 0.08, sharpness: 1900, for: 1.7), .ok)
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

    func testEndingAFocusPauseForTheHandKeepsTheBaselineAndAlignmentIsStillSeen() {
        withBaseline()
        feed(focus: 0.5, for: 2.6)
        XCTAssertEqual(monitor.state, .pausedFocus)
        monitor.endFocusPauseForHand()
        XCTAssertEqual(monitor.state, .ok)
        XCTAssertEqual(monitor.focusBaseline, 1.0, "the manual resume would have cleared it")
        // The picture is blank while the hand moves the stage: no focus pause comes of it.
        XCTAssertEqual(feed(viewClass: .blank, for: 5), .ok)
        // A phone that moved off the eyepiece is still seen.
        XCTAssertEqual(
            feed(alignment: reading(shift: 0.5), viewClass: .blank, for: 3.1), .pausedAlignment)
    }

    func testEndingForTheHandDoesNotEndAnAlignmentPause() {
        feed(alignment: reading(shift: 0.5), for: 3.1)
        XCTAssertEqual(monitor.state, .pausedAlignment)
        monitor.endFocusPauseForHand()
        XCTAssertEqual(monitor.state, .pausedAlignment)
    }
}
