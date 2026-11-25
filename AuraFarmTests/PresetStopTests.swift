import CoreVideo
import XCTest

@testable import AuraFarm

/// Counting at the stops of a preset path.
final class PresetStopTests: XCTestCase {
    private let size = CGSize(width: 640, height: 480)
    private let thresholds = LiveCountThresholds()

    // MARK: Skip rules

    private func reason(
        _ stage: LiveOrganismCounter.StillStage, tracking: TrackingState = .tracking,
        junk: Bool = false, paused: Bool = false, view: ViewClass = .sample, speed: Double = 0,
        still: Double = 0, since: Double? = nil, heat: HeatMode = .normal
    ) -> String? {
        LiveOrganismCounter.skipReason(
            tracking: tracking, isGhostOrSparseSkip: junk, monitorPaused: paused, viewClass: view,
            speedFraction: speed, stillSeconds: still, secondsSinceLastDetection: since,
            maxModelRunsPerSecond: 5, heat: heat, stillStage: stage)
    }

    func testAtAStopTheTrackersSayOnThePictureDoesNotApply() {
        XCTAssertNil(reason(.stop, tracking: .lost, view: .blank))
        XCTAssertNil(reason(.stop, junk: true))
        XCTAssertNil(reason(.stop, view: .blurry, speed: 0.9))
        XCTAssertNil(reason(.stop, still: 5, since: 0.5), "unchanged does not apply either")
        // Away from a stop they all do, as before.
        XCTAssertEqual(reason(.none, tracking: .lost), "not_tracking")
        XCTAssertEqual(reason(.none, junk: true), "junk_frame")
        XCTAssertEqual(reason(.none, view: .blank), "no_sample")
        XCTAssertEqual(reason(.none, speed: 0.9), "too_fast")
        XCTAssertEqual(reason(.none, still: 5, since: 0.5), "unchanged")
    }

    func testAtAStopTheOtherRulesStillHold() {
        XCTAssertEqual(reason(.stop, paused: true), "paused", "a focus pause")
        XCTAssertEqual(reason(.stop, view: .dark), "no_sample", "a dark view")
        XCTAssertEqual(reason(.stop, heat: .tooHot), "heat_critical")
        XCTAssertEqual(reason(.stop, since: 0.05), "rate", "the 5 a second cap")
        XCTAssertEqual(reason(.stop, since: 0.22, heat: .coolDown), "heat", "the cooling cap")
    }

    func testTheHandPreviewIgnoresThePictureWhenTheStageStandsStillButKeepsTheRefreshRule() {
        XCTAssertNil(reason(.hand, tracking: .paused, junk: true, view: .blank, speed: 0.9))
        XCTAssertEqual(reason(.hand, still: 5, since: 0.5), "unchanged", "looked at every second")
        XCTAssertNil(reason(.hand, still: 5, since: 1.2))
    }

    func testFramesBetweenStopsAreSkippedAndAStopAllowsThreeLooks() {
        var stops = PresetStopTracker()
        stops.isEnabled = true
        XCTAssertEqual(stops.skipReason(frameAt: 1), "between_stops")
        stops.begin(id: 1, column: 1, angles: .init(x: 90, y: 90), at: 10)
        XCTAssertEqual(stops.skipReason(frameAt: 9.9), "between_stops", "captured before the stop began")
        XCTAssertNil(stops.skipReason(frameAt: 10.1))
        for _ in 0..<3 { stops.noteLook() }
        XCTAssertEqual(stops.skipReason(frameAt: 10.5), "stop_done")
        stops.suspend()
        XCTAssertEqual(stops.skipReason(frameAt: 11), "between_stops")
    }

    // MARK: How long a stop is held

    func testAStopIsHeldForTwoLooksOrTwoSecondsAndNotWhenLooksCannotHappen() {
        var stops = PresetStopTracker()
        stops.begin(id: 1, column: 1, angles: .init(x: 1, y: 2), at: 0)
        XCTAssertTrue(stops.holds(canLook: true))
        XCTAssertFalse(stops.holds(canLook: false), "counting off, no model, too hot: no waiting")
        stops.noteLook()
        XCTAssertTrue(stops.holds(canLook: true))
        stops.noteLook()
        XCTAssertFalse(stops.holds(canLook: true), "two looks")

        var slow = PresetStopTracker()
        slow.begin(id: 2, column: 1, angles: .init(x: 1, y: 2), at: 0)
        for second in 0...19 { slow.tick(at: Double(second) * 0.1, inFocusPause: false) }
        XCTAssertTrue(slow.holds(canLook: true), "1.9 s")
        slow.tick(at: 2.0, inFocusPause: false)
        slow.tick(at: 2.1, inFocusPause: false)
        XCTAssertFalse(slow.holds(canLook: true), "2 s in all")
    }

    func testTimeInAFocusPauseDoesNotCountTowardsTheTwoSeconds() {
        var stops = PresetStopTracker()
        stops.begin(id: 1, column: 1, angles: .init(x: 1, y: 2), at: 0)
        stops.tick(at: 0, inFocusPause: false)
        for step in 1...50 { stops.tick(at: Double(step) * 0.1, inFocusPause: true) }
        XCTAssertEqual(stops.stop?.waited ?? -1, 0, accuracy: 1e-9)
        XCTAssertTrue(stops.holds(canLook: true))
    }

    func testPausingAndResumingAtTheSamePlaceKeepsTheStopAndItsLooks() {
        var stops = PresetStopTracker()
        stops.begin(id: 7, column: 2, angles: .init(x: 5, y: 6), at: 0)
        stops.noteLook()
        stops.suspend()
        stops.noteLook()  // suspended: no look
        XCTAssertNil(stops.begin(id: 7, column: 2, angles: .init(x: 5, y: 6), at: 9))
        XCTAssertEqual(stops.stop?.id, 7)
        XCTAssertEqual(stops.stop?.looks, 1)
        XCTAssertEqual(stops.stop?.beganAt, 0, "frames from before the pause still belong to it")
        let finished = stops.begin(id: 8, column: 2, angles: .init(x: 5, y: 7), at: 12)
        XCTAssertEqual(finished?.id, 7)
        XCTAssertEqual(stops.stopsWithLooks, 1, "a stop with a look is a field scanned")
    }

    func testFieldsScannedAreTheStopsThatHadALook() {
        var stops = PresetStopTracker()
        stops.begin(id: 1, column: 1, angles: .init(x: 1, y: 1), at: 0)
        stops.noteLook()
        stops.begin(id: 2, column: 1, angles: .init(x: 1, y: 2), at: 5)  // no look
        stops.begin(id: 3, column: 1, angles: .init(x: 1, y: 3), at: 9)
        stops.noteLook()
        XCTAssertEqual(stops.stopsWithLooks, 2)
        stops.end()
        XCTAssertEqual(stops.stopsWithLooks, 2)
        XCTAssertEqual(stops.firstAngles, StageAngles(x: 1, y: 1))
        stops.reset()
        XCTAssertEqual(stops.stopsWithLooks, 0)
    }

    // MARK: Where a stop is

    func testAnglesBecomeGuideFieldsInTheArrowsDirectionsInAllFourFlipCases() {
        func fields(_ flipX: Bool, _ flipY: Bool) -> CGPoint {
            PresetStopGeometry(fieldsPerDegreeX: 0.1, fieldsPerDegreeY: 0.2, flipX: flipX, flipY: flipY)
                .guideFields(dx: 2, dy: 3)
        }
        // Compared to a tolerance, not exactly: 0.2 * 3 is 0.6000000000000001 in binary.
        func assertFields(
            _ flipX: Bool, _ flipY: Bool, _ x: CGFloat, _ y: CGFloat, line: UInt = #line
        ) {
            let point = fields(flipX, flipY)
            XCTAssertEqual(point.x, x, accuracy: 1e-9, line: line)
            XCTAssertEqual(point.y, y, accuracy: 1e-9, line: line)
        }
        // Up is more Y degrees (the view goes up: smaller y), Left fewer X degrees.
        assertFields(false, false, 0.2, -0.6)
        assertFields(true, false, -0.2, -0.6)
        assertFields(false, true, 0.2, 0.6)
        assertFields(true, true, -0.2, 0.6)
    }

    func testTheCellIsASquareOfPointEightBoxesAtTheCentreOfTheCircle() {
        let cell = PresetStopCell.rect(centre: CGPoint(x: 320, y: 240), boxSide: 100, fields: 0.8)
        XCTAssertEqual(cell, CGRect(x: 280, y: 200, width: 80, height: 80))
    }

    // MARK: Counting at stops

    private func detection(_ x: Double, _ y: Double = 240, side: Double = 40, label: String = "Volvox")
        -> OrganismDetector.Detection
    {
        OrganismDetector.Detection(
            label: label, confidence: 0.9,
            box: CGRect(
                x: (x - side / 2) / size.width, y: 1 - (y + side / 2) / size.height,
                width: side / size.width, height: side / size.height))
    }

    private let cell = CGRect(x: 280, y: 200, width: 80, height: 80)

    @discardableResult
    private func look(
        _ counter: inout LiveOrganismCounter, stop: Int, _ found: [OrganismDetector.Detection],
        tracker: CGPoint = .zero
    ) -> LiveOrganismCounter.FrameResult {
        counter.update(
            detections: found, pictureMoved: CGPoint(x: 99, y: 99), trackerPosition: tracker,
            frameSize: size, fieldCircle: nil, seconds: 1, column: 1,
            stop: .init(id: stop, cell: cell))
    }

    func testOnlyDetectionsWithTheirCentreInTheCellCountAndTheOthersAreDrawnGrey() {
        var counter = LiveOrganismCounter()
        look(&counter, stop: 1, [detection(320), detection(500)])
        let second = look(&counter, stop: 1, [detection(320), detection(500)])
        XCTAssertEqual(counter.helperTotal, 1, "two sightings of the one inside")
        XCTAssertEqual(second.outsideCell, 1)
        let grey = counter.visibleBoxes.filter { $0.status == .seenOnce }
        XCTAssertEqual(grey.count, 1)
        XCTAssertEqual(grey.first?.box.midX ?? 0, 500, accuracy: 1)
    }

    func testTheTracksAreClearedBetweenStopsButTheCountsStay() {
        var counter = LiveOrganismCounter()
        look(&counter, stop: 1, [detection(300)])
        look(&counter, stop: 1, [detection(300)])
        XCTAssertEqual(counter.tallyTotal, 1)
        // 36 px away: the same track in a running tally (the match distance is 40), not dirt (20).
        look(&counter, stop: 2, [detection(336)], tracker: CGPoint(x: 500, y: 0))
        XCTAssertEqual(counter.tallyTotal, 1, "one sighting at the new stop is not a count")
        look(&counter, stop: 2, [detection(336)], tracker: CGPoint(x: 500, y: 0))
        XCTAssertEqual(counter.tallyTotal, 2)
    }

    func testTheSameOrganismInTwoOverlappingStopsCountsOnceOnTheMap() {
        var counter = LiveOrganismCounter()
        let first = CGPoint(x: 10, y: 0)
        // The stage moved 30 px: the same slide point shows 30 px along on the frame.
        let second = CGPoint(x: 40, y: 0)
        look(&counter, stop: 1, [detection(320)], tracker: first)
        look(&counter, stop: 1, [detection(320)], tracker: first)
        look(&counter, stop: 2, [detection(350)], tracker: second)
        look(&counter, stop: 2, [detection(350)], tracker: second)
        XCTAssertEqual(counter.tallyTotal, 2)
        XCTAssertEqual(counter.helperTotal, 1, "the map removes the repeat")
    }

    func testLensDirtCountsAtMostOnceOverFiveStops() {
        var counter = LiveOrganismCounter()
        var dirt = 0
        for stop in 1...5 {
            // The stage moves, the dirt stays at the same place on the frame.
            let tracker = CGPoint(x: Double(stop) * 100, y: 0)
            look(&counter, stop: stop, [detection(330)], tracker: tracker)
            dirt += look(&counter, stop: stop, [detection(330)], tracker: tracker).dirt
        }
        XCTAssertEqual(counter.tallyTotal, 1)
        XCTAssertEqual(counter.helperTotal, 1)
        XCTAssertGreaterThan(dirt, 0)
    }

    func testAResultThatArrivesLateIsCountedIntoItsOwnStop() {
        var counter = LiveOrganismCounter()
        look(&counter, stop: 1, [detection(300)])
        look(&counter, stop: 2, [detection(340)], tracker: CGPoint(x: 200, y: 0))
        // The second look of stop 1 arrives after stop 2's first result.
        look(&counter, stop: 1, [detection(300)])
        XCTAssertEqual(counter.tallyTotal, 1, "stop 1 had its two sightings")
        // And stop 2's own track is still there.
        look(&counter, stop: 2, [detection(340)], tracker: CGPoint(x: 200, y: 0))
        XCTAssertEqual(counter.tallyTotal, 2)
        // A stop older than the one before is dropped.
        look(&counter, stop: 3, [detection(300)], tracker: CGPoint(x: 400, y: 0))
        look(&counter, stop: 1, [detection(300)])
        XCTAssertEqual(counter.lateStopDrops, 1)
        XCTAssertEqual(counter.tallyTotal, 2)
    }

    func testWithoutAStopNothingChanges() {
        var counter = LiveOrganismCounter()
        let one = counter.update(
            detections: [detection(320)], pictureMoved: .zero, trackerPosition: .zero,
            frameSize: size, fieldCircle: nil, seconds: 1, column: 1)
        XCTAssertEqual(one.outsideCell, 0)
        XCTAssertEqual(one.dirt, 0)
        XCTAssertTrue(counter.ignoredBoxes.isEmpty)
        counter.update(
            detections: [detection(320)], pictureMoved: .zero, trackerPosition: .zero,
            frameSize: size, fieldCircle: nil, seconds: 2, column: 1)
        XCTAssertEqual(counter.helperTotal, 1)
    }

    // MARK: Through the session

    func testAStopsResultsAreAddedUpForItsLogEvent() {
        let session = LiveCountSession(detect: { _, _ in
            ([self.detection(320)], OrganismDetector.Timing())
        })
        for _ in 0..<2 {
            _ = session.process(
                buffer: SyntheticFrame.make(width: 64, height: 48) { _, _ in 100 }, skipReason: nil,
                pictureMoved: .zero, trackerPosition: .zero, frameSize: size, fieldCircle: nil,
                seconds: 1, column: 1, stop: .init(id: 4, cell: cell))
            session.drain()
        }
        let totals = session.totals(forStop: 4)
        XCTAssertEqual(totals?.results, 2)
        XCTAssertEqual(totals?.counted, 1)
        XCTAssertNil(session.totals(forStop: 5))
    }
}
