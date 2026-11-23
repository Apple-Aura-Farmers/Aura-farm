import XCTest

@testable import AuraFarm

/// Performance step 2: after setup the run monitor reads focus about three times a second and
/// alignment once a second, by the readings' own clock, and still pauses and resumes on time.
final class RunCadenceTests: XCTestCase {
    private let confirmed = FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 300)
    private let tick = 0.12

    private func alignment(shift: Double) -> AlignmentReading {
        var reading = AlignmentReading()
        reading.found = true
        reading.circle = FieldCircle(centre: CGPoint(x: 640 + shift * 300, y: 360), radius: 300)
        reading.roundness = 0.95
        return reading
    }

    /// Feeds `duration` seconds at 0.12 s a reading, measuring focus and alignment at the run's
    /// intervals and passing nil in between. Returns the state and how often each was measured.
    private func run(
        _ monitor: inout RunMonitor, from start: Double, for duration: Double,
        focus: Double = 1, sharpness: Double = 2000, shift: Double = 0
    ) -> (state: RunMonitorState, end: Double, focusReads: Int, alignmentReads: Int) {
        var time = start
        var lastFocus: Double?
        var lastAlignment: Double?
        var focusReads = 0
        var alignmentReads = 0
        while time - start < duration - 1e-9 {
            time += tick
            var index: Double?
            var geometry: AlignmentReading?
            if lastFocus.map({ time - $0 >= LabSetupSession.runFocusIntervalSeconds - 1e-9 }) ?? true {
                lastFocus = time
                index = focus
                focusReads += 1
            }
            if lastAlignment.map({ time - $0 >= LabSetupSession.runAlignmentIntervalSeconds - 1e-9 })
                ?? true
            {
                lastAlignment = time
                geometry = alignment(shift: shift)
                alignmentReads += 1
            }
            monitor.update(
                alignment: geometry, confirmedCircle: confirmed, focusIndex: index,
                boxSharpness: sharpness, viewClass: .sample, tracking: .tracking, seconds: time)
        }
        return (monitor.state, time, focusReads, alignmentReads)
    }

    func testTenSecondsAreReadAboutThreeAndOnceASecond() {
        var monitor = RunMonitor()
        monitor.setFocusBaseline(1)
        let result = run(&monitor, from: 0, for: 10)
        XCTAssertEqual(Double(result.focusReads), 28, accuracy: 3, "about three a second")
        XCTAssertEqual(Double(result.alignmentReads), 10, accuracy: 1, "about one a second")
    }

    func testARealFocusLossStillPausesAfterTwoAndAHalfSecondsAndResumesAfterOneAndAHalf() {
        var monitor = RunMonitor()
        monitor.setFocusBaseline(1)
        var result = run(&monitor, from: 0, for: 8)
        XCTAssertEqual(result.state, .ok)
        // Run A: the index and the sharpness both fall.
        result = run(&monitor, from: result.end, for: 2.3, focus: 0.3, sharpness: 500)
        XCTAssertEqual(result.state, .ok, "2.3 s is not enough")
        result = run(&monitor, from: result.end, for: 0.6, focus: 0.3, sharpness: 500)
        XCTAssertEqual(result.state, .pausedFocus)
        result = run(&monitor, from: result.end, for: 0.6, focus: 1, sharpness: 2000)
        XCTAssertEqual(result.state, .pausedFocus, "under a second of good readings")
        result = run(&monitor, from: result.end, for: 0.7, focus: 1, sharpness: 2000)
        XCTAssertEqual(result.state, .pausedFocus, "1.3 s of good readings")
        result = run(&monitor, from: result.end, for: 0.5, focus: 1, sharpness: 2000)
        XCTAssertEqual(result.state, .ok, "over 1.5 s of good readings")
    }

    func testARealPhoneMoveStillPausesAfterThreeSecondsAndResumesAfterOne() {
        var monitor = RunMonitor()
        var result = run(&monitor, from: 0, for: 3)
        XCTAssertEqual(result.state, .ok)
        result = run(&monitor, from: result.end, for: 2.5, shift: 0.25)
        XCTAssertEqual(result.state, .ok, "2.5 s is not enough")
        result = run(&monitor, from: result.end, for: 1.5, shift: 0.25)
        XCTAssertEqual(result.state, .pausedAlignment)
        result = run(&monitor, from: result.end, for: 0.6, shift: 0)
        XCTAssertEqual(result.state, .pausedAlignment, "under a second back")
        result = run(&monitor, from: result.end, for: 1.5, shift: 0)
        XCTAssertEqual(result.state, .ok)
    }

    // MARK: The session

    private func texturedFrame() -> CVPixelBuffer {
        SyntheticFrame.make(width: 1280, height: 720) { x, y in
            guard hypot(Double(x) - 640, Double(y) - 360) <= 300 else { return 10 }
            return UInt8(170 + 60 * sin(Double(x) * 0.5) * sin(Double(y) * 0.5))
        }
    }

    func testTheSessionMeasuresByTimeAfterSetupAndByFrameDuringIt() throws {
        let pipeline = SlideMovementPipeline()
        pipeline.requiresReview = true
        let session = LabSetupSession(skippingAlignAndFocus: true)
        let frame = texturedFrame()
        var seconds = 0.0
        func feed() -> LabSetupSession.Output? {
            seconds += 0.12
            return session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        }
        // During the field step alignment is taken on every 3rd frame.
        var last = session.alignmentMilliseconds
        var taken = 0
        for _ in 0..<30 {
            _ = feed()
            if session.alignmentMilliseconds != last { taken += 1 }
            last = session.alignmentMilliseconds
        }
        XCTAssertEqual(taken, 10, "every 3rd of 30 frames")
        pipeline.confirmField()
        _ = feed()
        session.skipStage()
        XCTAssertEqual(session.step, .done)

        var focusReads = 0
        var alignmentReads = 0
        for _ in 0..<83 {
            _ = feed()
            if session.info.monitor.focusIndex != nil { focusReads += 1 }
            if session.info.monitor.circleShift != nil { alignmentReads += 1 }
        }
        XCTAssertEqual(Double(focusReads), 28, accuracy: 3, "about three a second over 10 s")
        XCTAssertEqual(Double(alignmentReads), 10, accuracy: 1, "about one a second over 10 s")
    }

    // MARK: Gap guard

    func testALongGapWithNoFocusReadingClearsTheCountdown() {
        var monitor = RunMonitor()
        monitor.setFocusBaseline(1)
        func low(_ seconds: Double) -> RunMonitorState {
            monitor.update(
                alignment: nil, confirmedCircle: confirmed, focusIndex: 0.3, boxSharpness: 500,
                viewClass: .sample, tracking: .tracking, seconds: seconds)
        }
        // Two seconds of low readings, a 3 s gap, then one low reading.
        var time = 0.0
        while time < 2.0 {
            time += 0.36
            _ = low(time)
        }
        XCTAssertEqual(monitor.state, .ok, "not yet 2.5 s")
        time += 3
        XCTAssertEqual(low(time), .ok, "no immediate pause: the countdown starts again")
        // 2.5 s from that reading.
        var state = RunMonitorState.ok
        let restart = time
        while time - restart < 2.0 {
            time += 0.36
            state = low(time)
        }
        XCTAssertEqual(state, .ok, "under 2.5 s since the restart")
        while time - restart < 2.9 {
            time += 0.36
            state = low(time)
        }
        XCTAssertEqual(state, .pausedFocus)
    }
}
