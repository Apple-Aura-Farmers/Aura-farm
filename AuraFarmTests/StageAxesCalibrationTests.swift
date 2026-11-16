import XCTest

@testable import AuraFarm

/// Phase 2h part A1: the stage's two axes, measured one knob at a time.
final class StageAxesCalibrationTests: XCTestCase {
    private var calibration = StageAxesCalibration()
    private var seconds = 0.0
    /// Every progress `run` saw, in order.
    private var seen: [StageAxesProgress] = []

    /// Turns a knob along `degrees` from screen +x for `fields`, `noise` of wobble across it,
    /// reading every 0.05 field. Returns the last progress.
    @discardableResult
    private func run(
        from start: CGPoint, degrees: Double, fields: Double, noise: Double = 0,
        tracking: TrackingState = .tracking
    ) -> StageAxesProgress {
        var progress = calibration.update(position: start, tracking: tracking, seconds: seconds)
        let angle = degrees * .pi / 180
        var along = 0.0
        var wobble = 0.5
        while along < fields {
            along += 0.05
            seconds += 0.1
            wobble = (wobble * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
            let across = (wobble / 233280 - 0.5) * 2 * noise
            progress = calibration.update(
                position: CGPoint(
                    x: Double(start.x) + along * cos(angle) - across * sin(angle),
                    y: Double(start.y) + along * sin(angle) + across * cos(angle)),
                tracking: tracking, seconds: seconds)
            seen.append(progress)
        }
        return progress
    }

    private func endOfLast(_ degrees: Double, _ fields: Double, from start: CGPoint) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(
            x: Double(start.x) + fields * cos(angle), y: Double(start.y) + fields * sin(angle))
    }

    func testATenDegreeTiltWithNoiseGivesTiltTen() throws {
        run(from: .zero, degrees: 10, fields: 2.2, noise: 0.03)
        let end = endOfLast(10, 2.2, from: .zero)
        let progress = run(from: end, degrees: 90 + 9, fields: 2.2, noise: 0.03)
        XCTAssertEqual(progress.step, .done)
        let axes = try XCTUnwrap(calibration.result)
        XCTAssertEqual(axes.tiltDegrees, 10, accuracy: 0.5)
        XCTAssertEqual(axes.skewDegrees, 1, accuracy: 0.6)
        XCTAssertTrue(progress.message.hasPrefix("Stage straightened ✓ (tilt "))
    }

    func testTheStraighteningMapsBothAxesOntoScreenXAndY() throws {
        run(from: .zero, degrees: 10.4, fields: 2.2)
        run(from: endOfLast(10.4, 2.2, from: .zero), degrees: 90 + 8.8, fields: 2.2)
        let axes = try XCTUnwrap(calibration.result)
        let map = axes.straightening
        let x = axes.xDirection.applying(map)
        let y = axes.yDirection.applying(map)
        XCTAssertEqual(Double(x.y), 0, accuracy: 0.01)
        XCTAssertGreaterThan(Double(x.x), 0)
        XCTAssertEqual(Double(y.x), 0, accuracy: 0.01)
        XCTAssertGreaterThan(Double(y.y), 0)
        XCTAssertEqual(Double(map.a * map.d - map.b * map.c), 1, accuracy: 1e-9, "determinant 1")
        XCTAssertEqual(map.tx, 0)
        XCTAssertEqual(map.ty, 0)
    }

    func testACurvedRunWithBothKnobsIsRejectedAndRestarts() {
        // A bend: half along x, then half along y. Far from one straight line.
        run(from: .zero, degrees: 0, fields: 1.5)
        var progress = run(from: CGPoint(x: 1.5, y: 0), degrees: 90, fields: 1.5)
        XCTAssertEqual(progress.step, .waitX)
        XCTAssertEqual(progress.message, StageAxesCalibration.rejectedMessage)
        XCTAssertNil(calibration.result)
        // It starts that axis again from here: a clean run is then accepted. The message is held
        // for 2.0 s (Phase 2l) and readings during it are not counted, so the run starts after it.
        seconds += StageAxesThresholds().messageHoldSeconds
        progress = run(from: CGPoint(x: 1.5, y: 1.5), degrees: 5, fields: 2.2)
        XCTAssertEqual(progress.step, .waitY)
    }

    func testANegativeRunGivesTheSameAxis() throws {
        run(from: .zero, degrees: 10, fields: 2.2)
        let forwardEnd = endOfLast(10, 2.2, from: .zero)
        run(from: forwardEnd, degrees: 99, fields: 2.2)
        let forward = try XCTUnwrap(calibration.result)

        calibration = StageAxesCalibration()
        let start = CGPoint(x: 5, y: 5)
        run(from: start, degrees: 10 + 180, fields: 2.2)
        run(from: endOfLast(190, 2.2, from: start), degrees: 99 + 180, fields: 2.2)
        let backward = try XCTUnwrap(calibration.result)
        XCTAssertEqual(forward.tiltDegrees, backward.tiltDegrees, accuracy: 0.2)
        XCTAssertEqual(Double(forward.xDirection.x), Double(backward.xDirection.x), accuracy: 0.01)
        XCTAssertEqual(Double(forward.yDirection.y), Double(backward.yDirection.y), accuracy: 0.01)
    }

    func testAxesSixtyDegreesApartFailAndRestart() {
        run(from: .zero, degrees: 0, fields: 2.2)
        run(from: CGPoint(x: 2.2, y: 0), degrees: 60, fields: 2.2)
        XCTAssertTrue(seen.contains { $0.step == .failed(StageAxesCalibration.failedMessage) })
        XCTAssertNil(calibration.result)
        let next = calibration.update(position: CGPoint(x: 3, y: 2), tracking: .tracking, seconds: 99)
        XCTAssertEqual(next.step, .waitX, "back to the first axis")
    }

    func testLostOrPausedReadingsAreIgnored() {
        // A wild jump while lost or paused changes nothing.
        run(from: .zero, degrees: 10, fields: 1.0)
        _ = calibration.update(position: CGPoint(x: 50, y: -40), tracking: .lost, seconds: 50)
        _ = calibration.update(position: CGPoint(x: -30, y: 70), tracking: .paused, seconds: 51)
        _ = calibration.update(position: CGPoint(x: 8, y: 8), tracking: .matching, seconds: 52)
        let progress = run(from: endOfLast(10, 1.0, from: .zero), degrees: 10, fields: 1.3)
        XCTAssertEqual(progress.step, .waitY, "the x run was accepted from the tracked readings only")
    }

    func testProgressAndMessagesPerStep() {
        var progress = calibration.update(position: .zero, tracking: .tracking, seconds: 0)
        XCTAssertEqual(progress.message, StageAxesCalibration.waitXMessage)
        progress = run(from: .zero, degrees: 0, fields: 1.0)
        XCTAssertEqual(progress.travelFields, 1.0, accuracy: 0.06)
        progress = run(from: CGPoint(x: 1, y: 0), degrees: 0, fields: 1.3)
        XCTAssertEqual(progress.step, .waitY)
        XCTAssertEqual(progress.message, StageAxesCalibration.waitYMessage)
    }

    // MARK: Phase 2j part A1: sparse areas

    private func feedPaused(for duration: Double) -> StageAxesProgress {
        var progress = calibration.update(position: .zero, tracking: .paused, seconds: seconds)
        for _ in 0..<Int((duration * 10).rounded()) {
            seconds += 0.1
            progress = calibration.update(position: .zero, tracking: .paused, seconds: seconds)
        }
        return progress
    }

    func testTwelveTenthsOfASecondWithoutTrackingInWaitYSaysNothingToFollowAndOneReadingClearsIt() {
        XCTAssertEqual(run(from: .zero, degrees: 0, fields: 2.1).step, .waitY)
        let lost = feedPaused(for: 1.2)
        XCTAssertEqual(lost.message, StageAxesCalibration.nothingToFollowMessage)
        XCTAssertTrue(lost.nothingToFollow)
        seconds += 0.1
        let back = calibration.update(
            position: CGPoint(x: 2.1, y: 0), tracking: .tracking, seconds: seconds)
        XCTAssertEqual(back.message, StageAxesCalibration.waitYMessage)
        XCTAssertFalse(back.nothingToFollow)
    }

    func testAShortGapKeepsTheNormalMessageAndWaitXShowsTheParticlesHint() {
        XCTAssertEqual(
            calibration.update(position: .zero, tracking: .tracking, seconds: 0).hint,
            StageAxesCalibration.particlesHint)
        let short = feedPaused(for: 0.8)
        XCTAssertEqual(short.message, StageAxesCalibration.waitXMessage)
        XCTAssertFalse(short.nothingToFollow)
    }

    // MARK: Phase 2l hold, Phase 2m pause between the axes

    private func xDone() {
        XCTAssertEqual(run(from: .zero, degrees: 0, fields: 2.0).step, .waitY)
    }

    func testARejectionMessageIsHeldForTwoSecondsAndTheBarDoesNotFillMeanwhile() {
        // A bend, along x then along y: "Keep to one knob".
        var position = CGPoint.zero
        var rejectedAt: Double?
        _ = calibration.update(position: position, tracking: .tracking, seconds: 0)
        for index in 1...60 where rejectedAt == nil {
            if index <= 30 { position.x += 0.05 } else { position.y += 0.05 }
            let now = Double(index) * 0.1
            let progress = calibration.update(position: position, tracking: .tracking, seconds: now)
            if progress.message == StageAxesCalibration.rejectedMessage { rejectedAt = now }
        }
        let start = try? XCTUnwrap(rejectedAt)
        XCTAssertNotNil(start)
        let from = start ?? 0
        let held = calibration.update(position: position, tracking: .tracking, seconds: from + 1.9)
        XCTAssertEqual(held.message, StageAxesCalibration.rejectedMessage)
        XCTAssertEqual(held.travelFields, 0)
        XCTAssertTrue(held.isHeld)
        let after = calibration.update(position: position, tracking: .tracking, seconds: from + 2.0)
        XCTAssertEqual(after.message, StageAxesCalibration.waitXMessage)
        XCTAssertFalse(after.isHeld)
    }

    func testTheFailureMessageIsHeldToo() {
        xDone()
        // Y at 60 degrees from x: accepted as a straight run, then refused for the axes angle.
        var position = CGPoint(x: 2.0, y: 0)
        var failedAt: Double?
        var progress = StageAxesProgress(step: .waitY, travelFields: 0, message: "")
        for _ in 0..<80 where failedAt == nil {
            seconds += 0.1
            position.x += 0.025
            position.y += 0.0433
            progress = calibration.update(position: position, tracking: .tracking, seconds: seconds)
            if progress.step == .failed(StageAxesCalibration.failedMessage) { failedAt = seconds }
        }
        let from = failedAt ?? 0
        XCTAssertGreaterThan(from, 0)
        XCTAssertTrue(progress.isHeld)
        let held = calibration.update(position: position, tracking: .tracking, seconds: from + 1.9)
        XCTAssertEqual(held.step, .failed(StageAxesCalibration.failedMessage))
        let after = calibration.update(position: position, tracking: .tracking, seconds: from + 2.0)
        XCTAssertEqual(after.step, .waitX)
    }

    func testXMovementForHalfASecondAfterXIsAcceptedIsNotAddedToY() {
        xDone()
        // The X knob keeps turning for 0.4 s: 4 readings, 0.1 field each.
        var position = CGPoint(x: 2.0, y: 0)
        for _ in 0..<4 {
            seconds += 0.1
            position.x += 0.1
            _ = calibration.update(position: position, tracking: .tracking, seconds: seconds)
        }
        let progress = run(from: position, degrees: 90, fields: 2.2)
        XCTAssertEqual(progress.step, .done, "a clean Y run is accepted, not refused as a bend")
        XCTAssertNotNil(calibration.result)
    }

    func testThePauseShowsTheMessageWithTheBarFullAndTheStepStaysWaitY() {
        let accepted = run(from: .zero, degrees: 0, fields: 2.0)
        XCTAssertEqual(accepted.step, .waitY)
        XCTAssertEqual(accepted.message, StageAxesCalibration.xDoneMessage)
        XCTAssertTrue(accepted.isPause)
        XCTAssertEqual(accepted.travelFields, 2.0, accuracy: 1e-9)
        let during = calibration.update(
            position: CGPoint(x: 2.2, y: 0), tracking: .tracking, seconds: seconds + 0.3)
        XCTAssertEqual(during.step, .waitY)
        XCTAssertEqual(during.message, StageAxesCalibration.xDoneMessage)
        let after = calibration.update(
            position: CGPoint(x: 2.2, y: 0), tracking: .tracking, seconds: seconds + 0.5)
        XCTAssertEqual(after.step, .waitY)
        XCTAssertEqual(after.message, StageAxesCalibration.waitYMessage)
        XCTAssertFalse(after.isPause)
        XCTAssertEqual(after.travelFields, 0)
    }

    func testATiltedXThenYIsStillAccepted() throws {
        run(from: .zero, degrees: 10, fields: 2.2)
        let progress = run(from: endOfLast(10, 2.2, from: .zero), degrees: 99, fields: 2.2)
        XCTAssertEqual(progress.step, .done)
        XCTAssertEqual(try XCTUnwrap(calibration.result).tiltDegrees, 10, accuracy: 0.5)
    }
}
