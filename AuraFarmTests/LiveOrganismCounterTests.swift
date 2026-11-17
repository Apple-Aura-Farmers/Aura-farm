import XCTest

@testable import AuraFarm

final class LiveOrganismCounterTests: XCTestCase {
    private let size = CGSize(width: 640, height: 480)

    /// A detection whose box centre is at (`x`, `y`) frame pixels from the top left.
    private func detection(_ label: String = "Volvox", x: Double, y: Double = 240, side: Double = 40)
        -> OrganismDetector.Detection
    {
        OrganismDetector.Detection(
            label: label, confidence: 0.9,
            box: CGRect(
                x: (x - side / 2) / 640, y: 1 - (y + side / 2) / 480, width: side / 640,
                height: side / 480))
    }

    private func feed(
        _ counter: inout LiveOrganismCounter, _ detections: [OrganismDetector.Detection],
        moved: Double = 0, position: Double = 0, column: Int = 1, circle: FieldCircle? = nil
    ) {
        counter.update(
            detections: detections, pictureMoved: CGPoint(x: moved, y: 0),
            trackerPosition: CGPoint(x: position, y: 0), frameSize: size, fieldCircle: circle,
            seconds: 0, column: column)
    }

    func testAnOrganismSeenInFiveFramesWhileTheSlideMovesIsCountedOnce() {
        var counter = LiveOrganismCounter()
        for index in 0..<5 {
            feed(
                &counter, [detection(x: 200 + Double(index) * 10)], moved: index == 0 ? 0 : 10,
                position: Double(index) * 10)
        }
        XCTAssertEqual(counter.helperTotal, 1)
        XCTAssertEqual(counter.tallyTotal, 1)
    }

    func testSeenAgainOnColumnTwoIsOneOnTheMapAndTwoInTheTally() {
        var counter = LiveOrganismCounter()
        for _ in 0..<5 { feed(&counter, [detection(x: 200)]) }
        for _ in 0..<100 { feed(&counter, []) }
        // Column 2: the content has moved 90 px, so the same organism shows 90 px along.
        for _ in 0..<5 { feed(&counter, [detection(x: 290)], position: 90, column: 2) }
        XCTAssertEqual(counter.tallyTotal, 2)
        XCTAssertEqual(counter.helperTotal, 1)
        XCTAssertTrue(counter.visibleBoxes.contains { $0.status == .repeatOnMap })
    }

    func testTwoLabelsAtTheSamePointBothCount() {
        var counter = LiveOrganismCounter()
        for _ in 0..<3 {
            feed(&counter, [detection("Volvox", x: 200), detection("Nematode", x: 200)])
        }
        XCTAssertEqual(counter.helperTotal, 2)
        XCTAssertEqual(counter.helperCountByLabel, ["Volvox": 1, "Nematode": 1])
    }

    func testADetectionSeenInOneFrameIsNotCounted() {
        var counter = LiveOrganismCounter()
        feed(&counter, [detection(x: 200)])
        XCTAssertEqual(counter.visibleBoxes.first?.status, .seenOnce)
        feed(&counter, [])
        XCTAssertEqual(counter.helperTotal, 0)
        XCTAssertEqual(counter.tallyTotal, 0)
    }

    func testSkippedFramesShiftsAreCarriedSoTheTrackSurvivesTheGap() {
        var counter = LiveOrganismCounter()
        feed(&counter, [detection(x: 100)])
        for _ in 0..<5 { counter.skip(pictureMoved: CGPoint(x: 10, y: 0), reason: "too_fast") }
        // 5 skipped frames and this one: the picture moved 60 px.
        feed(&counter, [detection(x: 160)], moved: 10, position: 60)
        XCTAssertEqual(counter.tallyTotal, 1, "one organism, not two tracks")
        XCTAssertEqual(counter.framesSkippedByReason, ["too_fast": 5])
        XCTAssertEqual(counter.framesCounted, 2)
    }

    func testADetectionOutsideTheFieldCircleIsDroppedAndCounted() {
        var counter = LiveOrganismCounter()
        let circle = FieldCircle(centre: CGPoint(x: 320, y: 240), radius: 100)
        for _ in 0..<3 { feed(&counter, [detection(x: 600)], circle: circle) }
        XCTAssertEqual(counter.helperTotal, 0)
        XCTAssertEqual(counter.lastResult.outsideField, 1)
        for _ in 0..<3 { feed(&counter, [detection(x: 330)], circle: circle) }
        XCTAssertEqual(counter.helperTotal, 1)
    }

    func testSkipReasonsAreCheckedInOrder() {
        func reason(
            _ tracking: TrackingState = .tracking, junk: Bool = false, paused: Bool = false,
            _ viewClass: ViewClass = .sample, speed: Double = 0.05
        ) -> String? {
            LiveOrganismCounter.skipReason(
                tracking: tracking, isGhostOrSparseSkip: junk, monitorPaused: paused,
                viewClass: viewClass, speedFraction: speed)
        }
        XCTAssertNil(reason())
        XCTAssertNil(reason(.tracking, .thin))
        XCTAssertEqual(reason(.matching, junk: true, paused: true, .blank, speed: 1), "not_tracking")
        XCTAssertEqual(reason(junk: true, paused: true, .blank, speed: 1), "junk_frame")
        XCTAssertEqual(reason(paused: true, .blank, speed: 1), "paused")
        XCTAssertEqual(reason(.tracking, .blurry, speed: 1), "no_sample")
        XCTAssertEqual(reason(speed: 0.2), "too_fast")
    }

    func testNothingIsCountedBeforeTheFirstSpotOfColumnOneThroughTheGuide() {
        let route = ScriptedRoute()
        var activeBefore = false
        route.feed(move: ScriptedRoute.left, times: 15)
        activeBefore = activeBefore || route.guide.countingActive
        route.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: true), times: 24)
        activeBefore = activeBefore || route.guide.countingActive
        route.feed(move: ScriptedRoute.right, times: 6)
        activeBefore = activeBefore || route.guide.countingActive
        XCTAssertFalse(activeBefore, "setup, the left-edge run and the inset trip are not counted")
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        XCTAssertEqual(route.guide.placements.count, 1)
        XCTAssertTrue(route.guide.countingActive)
        route.guide.endNow()
        XCTAssertFalse(route.guide.countingActive)
    }

    /// The tracker's frame shift and position against real frames: content moving right, then down.
    func testPictureMovedAndSlidePositionSignsAgainstARealTracker() {
        let side = 256
        let texture = SyntheticFrame.smoothNoise(size: side)
        let frameSize = CGSize(width: side, height: side)
        let box = EyepieceField.centreSquare(frameSize: frameSize)
        func frame(shiftedBy dx: Int, _ dy: Int) -> CVPixelBuffer {
            SyntheticFrame.make(width: side, height: side) { x, y in
                UInt8(texture[min(max(y - dy, 0), side - 1) * side + min(max(x - dx, 0), side - 1)])
            }
        }
        for (dx, dy) in [(6, 0), (0, 6)] {
            let tracker = SlideTracker()
            var seconds = 0.0
            var reading: SlideTrackerReading?
            for index in 0..<8 {
                seconds += 0.1
                reading = tracker.track(
                    frame(shiftedBy: index * dx, index * dy), box: box, frameSize: frameSize,
                    seconds: seconds)
            }
            guard let reading else { return XCTFail("no reading") }
            // Content moves (+dx, +dy) a frame: a stationary thing is further along that way.
            let moved = LiveOrganismCounter.pictureMoved(frameShift: reading.frameShift)
            XCTAssertEqual(Double(moved.x), Double(dx), accuracy: 2)
            XCTAssertEqual(Double(moved.y), Double(dy), accuracy: 2)
            // The position is the content's displacement, with the same sign.
            XCTAssertEqual(Double(reading.position.x), Double(7 * dx), accuracy: 6)
            XCTAssertEqual(Double(reading.position.y), Double(7 * dy), accuracy: 6)
            // A thing at frame (100, 128) + position is at the same slide point as at (100, 128).
            let slide = SlideOrganismMap.slidePosition(
                boxCentre: CGPoint(x: 100 + reading.position.x, y: 128 + reading.position.y),
                frameCentre: CGPoint(x: 128, y: 128), trackerPosition: reading.position)
            XCTAssertEqual(Double(slide.x), -28, accuracy: 1e-6)
            XCTAssertEqual(Double(slide.y), 0, accuracy: 1e-6)
        }
    }
}
