import XCTest

@testable import AuraFarm

/// Telling an edge from the same picture out of focus: arrival, the half behind against the
/// last sharp frame, holding still, and blur leading to refocus. 10 readings a second.
final class EdgeConfirmationTests: XCTestCase {
    private var guide = GuidedSweep()
    private var seconds = 0.0
    private var position = CGPoint.zero
    private var index = 0
    private var steps: [(index: Int, step: GuideStep)] = []

    private struct Frame {
        var viewClass = ViewClass.thin
        var tracking = TrackingState.tracking
        var dx = 0.0
        var ahead: Double? = 400
        var behind: Double? = 400
        var aheadFocus: Double? = 1
        var behindFocus: Double? = 0.95
        var speed = 0.1
        var still = false
    }

    private func feed(_ frame: Frame, times: Int = 1) {
        for _ in 0..<times {
            seconds += 0.1
            index += 1
            position.x += frame.dx
            let step = guide.update(
                GuideReading(
                    seconds: seconds, position: position, tracking: frame.tracking,
                    unconfirmedGaps: 0, viewClass: frame.viewClass, speedFraction: frame.speed,
                    isStill: frame.still, aheadSharpness: frame.ahead, behindSharpness: frame.behind,
                    aheadFocusRatio: frame.aheadFocus, behindFocusRatio: frame.behindFocus))
            steps.append((index, step))
        }
    }

    /// Travelling left at 0.5 field a second for a second and a half, onto sample.
    private func travel() {
        feed(Frame(dx: -0.05), times: 15)
    }

    private var instructions: [GuideInstruction] { steps.map(\.step.instruction) }

    private func isChecking(_ instruction: GuideInstruction) -> Bool {
        if case .checkingEdge = instruction { return true }
        return false
    }

    private func isGoBack(_ instruction: GuideInstruction) -> Bool {
        if case .edgeGoBack = instruction { return true }
        return false
    }

    // MARK: 1-7

    func test1_aRealEdgeIsCheckedThenReached() throws {
        travel()
        let stop = index + 1
        feed(Frame(ahead: 50, behind: 250, still: true), times: 16)
        let checking = try XCTUnwrap(steps.first { isChecking($0.step.instruction) })
        let reached = try XCTUnwrap(steps.first { $0.step.instruction == .edgeReached })
        print("SCENARIO 1: checking at \(checking.index - stop), edgeReached at \(reached.index - stop)")
        XCTAssertEqual(checking.index, stop)
        XCTAssertTrue(
            (stop + 9)...(stop + 12) ~= reached.index, "about confirmSeconds: \(reached.index - stop)")
        XCTAssertTrue(reached.step.stateName.hasPrefix("column 1"), reached.step.stateName)
        XCTAssertFalse(instructions.contains(where: isGoBack))
    }

    func test2_aFlickDuringTravelIsNotAnEdge() {
        travel()
        feed(Frame(dx: -0.05, speed: 0.3))
        feed(
            Frame(
                viewClass: .blurry, ahead: 50, behind: 50, aheadFocus: 0.3, behindFocus: 0.3), times: 3)
        feed(Frame(dx: -0.05), times: 6)
        XCTAssertFalse(instructions.contains(.edgeReached))
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertFalse(instructions.contains(where: isChecking))
        XCTAssertFalse(instructions.contains(.refocus))
        XCTAssertEqual(instructions.last, .travel(direction: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(steps.last?.step.stateName, "find left edge")
    }

    func test3_aDefocusAtRestAsksForRefocusThroughoutAndTheRouteResumes() throws {
        travel()
        let slip = index + 1
        feed(
            Frame(viewClass: .blurry, ahead: 80, behind: 80, aheadFocus: 0.4, behindFocus: 0.4, still: true),
            times: 50)
        // From the 0.8 s the low detail needs to be a candidate, to the end of the 5 s.
        let blurred = steps.filter { $0.index >= slip + 8 && $0.index < slip + 50 }
        XCTAssertTrue(blurred.allSatisfy { $0.step.instruction == .refocus })
        XCTAssertFalse(instructions.contains(.edgeReached))
        XCTAssertFalse(instructions.contains(where: isGoBack))
        feed(Frame(dx: -0.05), times: 3)
        XCTAssertEqual(instructions.last, .travel(direction: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(steps.last?.step.stateName, "find left edge", "carries on where it was")
    }

    func test4_partialBlurWhileArrivingIsBlurNotAnEdge() {
        travel()
        feed(Frame(ahead: 50, behind: 150, behindFocus: 0.45, still: true), times: 25)
        XCTAssertFalse(instructions.contains(.edgeReached))
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertTrue(steps.suffix(20).allSatisfy { $0.step.instruction == .refocus })
    }

    func test5_aCreepingHelperIsCheckedButNotConfirmedUntilStill() throws {
        travel()
        feed(Frame(dx: -0.01, ahead: 50, behind: 250, speed: 0.1, still: false), times: 25)
        XCTAssertFalse(instructions.contains(.edgeReached), "still creeping")
        XCTAssertTrue(steps.suffix(10).allSatisfy { isChecking($0.step.instruction) })
        let still = index + 1
        feed(Frame(ahead: 50, behind: 250, still: true), times: 14)
        let reached = try XCTUnwrap(steps.first { $0.step.instruction == .edgeReached })
        XCTAssertTrue((still + 9)...(still + 12) ~= reached.index, "\(reached.index - still)")
    }

    func test6_theOvershootFallbackGoesBackUnlessItWasBlur() {
        // The last tracked reading had the half behind sharp: a real edge, overshot.
        travel()
        feed(
            Frame(
                viewClass: .blank, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
                behindFocus: nil), times: 40)
        XCTAssertTrue(instructions.contains(where: isGoBack))
        XCTAssertFalse(instructions.contains(.refocus))

        // The last tracked readings already had both halves blurred: not an edge.
        guide = GuidedSweep()
        (seconds, position, index, steps) = (0, .zero, 0, [])
        feed(Frame(dx: -0.05, aheadFocus: 0.3, behindFocus: 0.3), times: 15)
        feed(
            Frame(
                viewClass: .blank, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
                behindFocus: nil), times: 40)
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertTrue(steps.suffix(20).allSatisfy { $0.step.instruction == .refocus })
    }

    func test7_aKnockAtAStepRightLandingIsNotAFailedProbe() {
        let simulator = GuideSimulator(
            drop: SimulatedDrop(circles: [(.zero, 3)]), start: .zero)
        _ = simulator.run(until: { $0.stateName == "step right" })
        guide = simulator.guide
        seconds = simulator.guideSeconds
        position = simulator.guidePosition
        let probes = guide.failedProbes
        // 2 s of blur at the landing, helper still, no travel: then the picture comes back.
        feed(
            Frame(viewClass: .blurry, ahead: 50, behind: 50, aheadFocus: 0.3, behindFocus: 0.3, still: true),
            times: 20)
        feed(Frame(still: true), times: 5)
        XCTAssertEqual(guide.failedProbes, probes)
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertEqual(steps.last?.step.stateName, "step right")
    }

    // MARK: EdgeConfirmation on its own

    private func reading(
        _ seconds: Double, x: Double = 0, ahead: Double? = 50, behind: Double? = 250,
        behindFocus: Double? = 0.95, speed: Double = 0.05, still: Bool = true
    ) -> GuideReading {
        GuideReading(
            seconds: seconds, position: CGPoint(x: x, y: 0), tracking: .tracking,
            unconfirmedGaps: 0, viewClass: .thin, speedFraction: speed, isStill: still,
            aheadSharpness: ahead, behindSharpness: behind, aheadFocusRatio: 1,
            behindFocusRatio: behindFocus)
    }

    func testArrivalIsTheTravelAlongTheHeadingBeforeTheCandidateBegan() {
        var confirmation = EdgeConfirmation()
        let heading = CGPoint(x: -1, y: 0)
        for index in 0..<10 {
            _ = confirmation.update(
                reading: reading(Double(index) * 0.1, x: -0.05 * Double(index), ahead: 400, behind: 400),
                heading: heading, candidate: .none, since: nil)
        }
        let verdict = confirmation.update(
            reading: reading(1.0, x: -0.5), heading: heading, candidate: .halfEdge, since: 1.0)
        guard case .checking = verdict else { return XCTFail("expected checking, got \(verdict)") }
        XCTAssertEqual(confirmation.arrivalFields, 0.45, accuracy: 0.06)
    }

    func testAnUnvouchedCandidateWithNoArrivalIsBlurAndASpeedSpikeRestartsIt() {
        var confirmation = EdgeConfirmation()
        let heading = CGPoint(x: -1, y: 0)
        // At rest, the half behind not vouched for by the focus: blur.
        XCTAssertEqual(
            confirmation.update(
                reading: reading(0, behindFocus: nil), heading: heading, candidate: .halfEdge, since: 0),
            .blur)
        // Vouched for: checked, with progress only while still.
        var verdict = EdgeVerdict.none
        for index in 1...5 {
            verdict = confirmation.update(
                reading: reading(Double(index) * 0.1), heading: heading, candidate: .halfEdge, since: 0)
        }
        XCTAssertEqual(verdict, .checking(progress: 0.5))
        verdict = confirmation.update(
            reading: reading(0.6, speed: 0.3), heading: heading, candidate: .halfEdge, since: 0)
        XCTAssertEqual(verdict, .none, "a spike restarts it")
        XCTAssertEqual(confirmation.heldSeconds, 0)
        verdict = confirmation.update(
            reading: reading(0.7), heading: heading, candidate: .halfEdge, since: 0)
        guard case .checking(let progress) = verdict else {
            return XCTFail("expected checking, got \(verdict)")
        }
        XCTAssertEqual(progress, 0.1, accuracy: 1e-6, "from the spike on, not from before")
    }

    // MARK: The tracker

    func testBlurredContentGivesLowFocusRatiosAndAShiftedPatchGivesAboutOne() throws {
        let size = 256
        let texture = SyntheticFrame.smoothNoise(size: size)
        func frame(shift: Int, blurred: Bool) -> CVPixelBuffer {
            func at(_ x: Int, _ y: Int) -> Double {
                texture[min(max(y, 0), size - 1) * size + min(max(x - shift, 0), size - 1)]
            }
            return SyntheticFrame.make(width: size, height: size) { x, y in
                guard blurred else { return UInt8(at(x, y)) }
                var total = 0.0
                for dy in -2...2 { for dx in -2...2 { total += at(x + dx, y + dy) } }
                return UInt8(total / 25)
            }
        }
        let frameSize = CGSize(width: size, height: size)
        let box = EyepieceField.centreSquare(frameSize: frameSize)

        let blurTracker = SlideTracker()
        _ = blurTracker.track(frame(shift: 0, blurred: false), box: box, frameSize: frameSize, seconds: 0)
        let blurred = try XCTUnwrap(
            blurTracker.track(frame(shift: 0, blurred: true), box: box, frameSize: frameSize, seconds: 0.1)
                .halfFocusRatio)
        print("FOCUS blurred: \(blurred)")
        for ratio in [blurred.left, blurred.right, blurred.top, blurred.bottom] {
            XCTAssertLessThan(try XCTUnwrap(ratio), 0.6)
        }

        let shiftTracker = SlideTracker()
        _ = shiftTracker.track(frame(shift: 0, blurred: false), box: box, frameSize: frameSize, seconds: 0)
        let shifted = try XCTUnwrap(
            shiftTracker.track(frame(shift: 20, blurred: false), box: box, frameSize: frameSize, seconds: 0.1)
                .halfFocusRatio)
        print("FOCUS shifted: \(shifted)")
        for ratio in [shifted.left, shifted.right, shifted.top, shifted.bottom] {
            XCTAssertEqual(try XCTUnwrap(ratio), 1, accuracy: 0.2)
        }
        XCTAssertNil(
            SlideTracker().track(frame(shift: 0, blurred: false), box: box, frameSize: frameSize, seconds: 0)
                .halfFocusRatio)
    }

    // MARK: Simulator with knocks

    func testKnocksCauseNoFalseEdgesAndMostEdgesAreReachedAtTheCentre() {
        for (name, drop) in [
            ("round r=3", SimulatedDrop(circles: [(.zero, 3)])),
            ("square 8x8", SimulatedDrop.square(from: CGPoint(x: -4, y: -4), side: 8)),
        ] {
            for knocks in [false, true] {
                let simulator = GuideSimulator(drop: drop, start: .zero)
                simulator.soil = true
                simulator.knocks = knocks
                let result = simulator.run(maxReadings: 30000)
                let edges = result.edgesReached + result.edgesGoneBack
                let share = edges == 0 ? 0 : Double(result.edgesReached) / Double(edges)
                let label = "\(name) soil \(knocks ? "with" : "without") knocks"
                print(
                    String(
                        format:
                            "KNOCKS %@: readings %d finished %@ coverage %.1f%% edges %d reached %d share %.0f%% knocks %d false %d near knocks %d",
                        label, result.readings, "\(result.finished)", result.coverage * 100, edges,
                        result.edgesReached, share * 100, result.knocks, result.falseEdges,
                        result.falseEdgesNearKnocks))
                XCTAssertTrue(result.finished, label)
                XCTAssertGreaterThanOrEqual(result.coverage, 0.95, label)
                XCTAssertEqual(result.falseEdgesNearKnocks, 0, label)
                XCTAssertGreaterThanOrEqual(share, 0.8, label)
            }
        }
    }
}
