import CoreVideo
import XCTest

@testable import AuraFarm

/// Which boxes are drawn, and where: drawing only, the count never sees it.
final class LiveBoxGateTests: XCTestCase {
    private let size = CGSize(width: 64, height: 64)
    private let circle = FieldCircle(centre: CGPoint(x: 32, y: 32), radius: 20)
    private func box(_ x: Double, _ y: Double = 32) -> LiveCountInfo.Box {
        .init(
            id: 1, label: "Volvox", confidence: 0.9, rect: CGRect(x: x - 2, y: y - 2, width: 4, height: 4),
            status: .counted)
    }

    private func gate(now: Double = 10, trackedAt: Double? = 10, notBefore: Double = -.infinity)
        -> LiveBoxGate
    {
        LiveBoxGate(now: now, trackedAt: trackedAt, notBefore: notBefore)
    }

    // MARK: The gate on its own

    func testBoxesMoveWithThePicture() {
        let shown = gate().shown(
            [box(30)], shift: CGPoint(x: 6, y: -3), resultAt: 9.8, circle: circle)
        XCTAssertEqual(shown.first?.rect, box(30).rect.offsetBy(dx: 6, dy: -3))
    }

    func testABoxWhoseMovedCentreIsOutsideTheFieldIsNotDrawn() {
        XCTAssertEqual(
            gate().shown([box(40)], shift: .zero, resultAt: 9.8, circle: circle).count, 1)
        XCTAssertTrue(
            gate().shown([box(40)], shift: CGPoint(x: 15, y: 0), resultAt: 9.8, circle: circle).isEmpty)
    }

    func testHiddenAfterPointFourSecondsWithoutAShiftAndAfterOnePointFiveWithoutAResult() {
        XCTAssertEqual(
            gate(trackedAt: 9.7).shown([box(30)], shift: .zero, resultAt: 9.5, circle: nil).count, 1)
        XCTAssertTrue(
            gate(trackedAt: 9.5).shown([box(30)], shift: .zero, resultAt: 9.5, circle: nil).isEmpty)
        XCTAssertTrue(gate(trackedAt: nil).shown([box(30)], shift: .zero, resultAt: 9.5, circle: nil).isEmpty)
        XCTAssertEqual(
            gate().shown([box(30)], shift: .zero, resultAt: 8.6, circle: nil).count, 1, "1.4 s old")
        XCTAssertTrue(gate().shown([box(30)], shift: .zero, resultAt: 8.4, circle: nil).isEmpty)
        XCTAssertTrue(gate().shown([box(30)], shift: .zero, resultAt: nil, circle: nil).isEmpty)
    }

    func testAMoveStartHidesAtOnceAndALateResultFromBeforeItIsNotDrawn() {
        // The move is on: nothing is drawn.
        XCTAssertTrue(
            gate(notBefore: .infinity).shown([box(30)], shift: .zero, resultAt: 9.9, circle: nil).isEmpty)
        // Settled at 9.95: a result of a frame taken at 9.9 arrives late and is not drawn; the next is.
        XCTAssertTrue(
            gate(notBefore: 9.95).shown([box(30)], shift: .zero, resultAt: 9.9, circle: nil).isEmpty)
        XCTAssertEqual(
            gate(notBefore: 9.95).shown([box(30)], shift: .zero, resultAt: 9.99, circle: nil).count, 1)
    }

    func testAStillViewKeepsItsBoxesBecauseItIsLookedAtAboutEverySecond() {
        // Tracked, looked at 1.1 s ago (refreshSeconds is 1): still drawn.
        XCTAssertEqual(
            gate().shown([box(30)], shift: .zero, resultAt: 8.9, circle: circle).count, 1)
    }

    // MARK: Through the session

    private func countingSession() -> LiveCountSession {
        LiveCountSession(detect: { _, _ in
            (
                [
                    OrganismDetector.Detection(
                        label: "Volvox", confidence: 0.9, box: CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
                    )
                ],
                OrganismDetector.Timing()
            )
        })
    }

    private func process(
        _ session: LiveCountSession, skip: String?, shift: CGPoint, at seconds: Double
    ) {
        session.noteFrameShift(shift)
        _ = session.process(
            buffer: SyntheticFrame.make(width: 64, height: 64) { _, _ in 100 }, skipReason: skip,
            pictureMoved: shift, trackerPosition: .zero, frameSize: size, fieldCircle: nil,
            seconds: seconds, column: 1)
        session.drain()
    }

    func testCountedBoxesMoveWithSkippedFramesAndTheTracksAreNotTouched() {
        let session = countingSession()
        process(session, skip: nil, shift: .zero, at: 1)
        let first = session.info(isActive: true, frameSize: size).boxes
        XCTAssertEqual(first.count, 1)
        process(session, skip: "too_fast", shift: CGPoint(x: 3, y: 1), at: 1.1)
        process(session, skip: "too_fast", shift: CGPoint(x: 2, y: 2), at: 1.2)
        let drawn = session.info(
            isActive: true, frameSize: size, gate: LiveBoxGate(now: 1.2, trackedAt: 1.2)
        ).boxes
        XCTAssertEqual(drawn.first?.rect, first[0].rect.offsetBy(dx: 5, dy: 3))
        XCTAssertEqual(session.counter.visibleBoxes.first?.box, first[0].rect, "the track stays")
    }

    func testCountsAreTheSameWithAndWithoutHidingTheBoxes() {
        let session = countingSession()
        for index in 0..<4 {
            process(
                session, skip: index == 2 ? "too_fast" : nil, shift: CGPoint(x: 1, y: 0),
                at: 1 + Double(index) * 0.3)
        }
        let plain = session.info(isActive: true, frameSize: size)
        let hidden = session.info(
            isActive: true, frameSize: size,
            gate: LiveBoxGate(now: 99, trackedAt: nil, notBefore: .infinity))
        XCTAssertTrue(hidden.boxes.isEmpty)
        XCTAssertFalse(plain.boxes.isEmpty)
        XCTAssertEqual(hidden.total, plain.total)
        XCTAssertEqual(hidden.tallyTotal, plain.tallyTotal)
        XCTAssertEqual(hidden.labels, plain.labels)
        XCTAssertEqual(hidden.dots, plain.dots)
        XCTAssertEqual(hidden.framesCounted, plain.framesCounted)
        XCTAssertEqual(hidden.framesSkipped, plain.framesSkipped)
    }

    func testAResultWithNoDetectionsClearsTheBoxesAndTheNextOneShowsThemAgain() {
        var empty = false
        let session = LiveCountSession(detect: { _, _ in
            (
                empty
                    ? []
                    : [
                        OrganismDetector.Detection(
                            label: "Volvox", confidence: 0.9,
                            box: CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1))
                    ],
                OrganismDetector.Timing()
            )
        })
        let gate = LiveBoxGate(now: 1.6, trackedAt: 1.6)
        process(session, skip: nil, shift: .zero, at: 1)
        XCTAssertEqual(session.info(isActive: true, frameSize: size, gate: gate).boxes.count, 1)
        empty = true
        process(session, skip: nil, shift: .zero, at: 1.3)
        XCTAssertTrue(session.info(isActive: true, frameSize: size, gate: gate).boxes.isEmpty)
        empty = false
        process(session, skip: nil, shift: .zero, at: 1.6)
        XCTAssertEqual(session.info(isActive: true, frameSize: size, gate: gate).boxes.count, 1)
    }

    // MARK: Followed frames, counting off, and the move watch

    func testOnlyAFrameTheTrackerReallyFollowedCountsAsTracked() {
        let shift = CGPoint(x: 1, y: 0)
        XCTAssertTrue(LiveOrganismCounter.isFollowed(tracking: .tracking, frameShift: shift, reading: "ok"))
        XCTAssertTrue(LiveOrganismCounter.isFollowed(tracking: .tracking, frameShift: .zero, reading: "ok"))
        XCTAssertFalse(LiveOrganismCounter.isFollowed(tracking: .tracking, frameShift: nil, reading: "ok"))
        XCTAssertFalse(
            LiveOrganismCounter.isFollowed(tracking: .tracking, frameShift: shift, reading: "ghost"))
        XCTAssertFalse(
            LiveOrganismCounter.isFollowed(tracking: .tracking, frameShift: shift, reading: "sparse_skip"))
        XCTAssertFalse(LiveOrganismCounter.isFollowed(tracking: .paused, frameShift: shift, reading: "ok"))
        XCTAssertFalse(LiveOrganismCounter.isFollowed(tracking: .lost, frameShift: shift, reading: "ok"))
    }

    func testBoxesFollowThePictureWhileCountingIsOffAndOncePerFrame() {
        let session = countingSession()
        process(session, skip: nil, shift: .zero, at: 1)
        let first = session.info(isActive: true, frameSize: size).boxes
        // Counting is off: only the shift is noted, nothing goes to the counter or the detector.
        let framesBefore = session.counter.framesCounted
        session.noteFrameShift(CGPoint(x: 2, y: 1))
        session.noteFrameShift(CGPoint(x: 0, y: 3))
        session.drain()
        let drawn = session.info(
            isActive: false, frameSize: size, gate: LiveBoxGate(now: 1.2, trackedAt: 1.2)
        ).boxes
        XCTAssertEqual(drawn.first?.rect, first[0].rect.offsetBy(dx: 2, dy: 4))
        XCTAssertEqual(session.counter.framesCounted, framesBefore)
        XCTAssertTrue(session.counter.framesSkippedByReason.isEmpty)
        // A counting frame adds its shift once, not once here and once in process().
        process(session, skip: "too_fast", shift: CGPoint(x: 1, y: 0), at: 1.3)
        let after = session.info(
            isActive: true, frameSize: size, gate: LiveBoxGate(now: 1.3, trackedAt: 1.3)
        ).boxes
        XCTAssertEqual(after.first?.rect, first[0].rect.offsetBy(dx: 3, dy: 4))
    }

    func testSettlingWithNoMoveOrASecondTimeDoesNothing() {
        var watch = StageMoveWatch()
        XCTAssertFalse(watch.settle(at: 5), "no move in progress")
        XCTAssertEqual(watch.notBefore(now: 5, origin: 0, holdSeconds: 10), -.infinity)
        watch.start(at: 6)
        XCTAssertEqual(watch.notBefore(now: 6.5, origin: 0, holdSeconds: 10), .infinity)
        XCTAssertTrue(watch.settle(at: 7))
        XCTAssertEqual(watch.notBefore(now: 7.1, origin: 0, holdSeconds: 10), 7)
        XCTAssertFalse(watch.settle(at: 9), "a second settle changes nothing")
        XCTAssertEqual(watch.notBefore(now: 9.1, origin: 0, holdSeconds: 10), 7)
    }

    func testAMoveThatNeverSettlesReleasesAfterTheHoldButNotForOlderResults() {
        var watch = StageMoveWatch()
        watch.start(at: 100)
        XCTAssertEqual(watch.notBefore(now: 105, origin: 90, holdSeconds: 10), .infinity)
        XCTAssertEqual(
            watch.notBefore(now: 111, origin: 90, holdSeconds: 10), 10,
            "results from before the start stay hidden")
    }
}
