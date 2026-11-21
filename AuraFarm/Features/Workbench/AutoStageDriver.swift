#if DEBUG
    import CoreGraphics
    import Foundation
    import Observation

    /// Drives the Terraloka stage from the slide movement lab: measures how each servo moves the
    /// picture, hands the lab its stage axes, then follows the guide's target one small move at a
    /// time. Edges are still confirmed by the person; the stage stops while one is asked.
    @MainActor
    @Observable
    final class AutoStageDriver {
        enum Phase: Equatable {
            case disconnected
            case waitingForStageStep
            case calibrating(axis: StageAxis, travel: Double)
            case calibrated(summary: String)
            case following
            case waitingForEdgeAnswer
            case atLimit(StageAxis)
            case paused
            case failed(String)
        }

        let client = StageBLEClient()
        private(set) var phase = Phase.disconnected
        private(set) var lastMove = ""
        private(set) var mappingSummary = ""
        var chunkDegrees = 3
        /// The lab shows the picture straightened (and so measures the guide in straightened axes).
        var guideIsStraightened = true

        private let engine: SlideMovementLabModel
        private var mapping: StageServoMapping?
        private var calibration = StageAutoCalibration()
        private var collecting: (servo: StageAxis, angle: Double)?
        private var angleX = 90
        private var angleY = 90
        private var inFlight = false
        private var lastSettledAt = Date.distantPast
        private var moveSentAt = Date.distantPast
        private var userPaused = false
        private var lastServo = StageAxis.x
        private var isCalibrating = false
        /// Tracking broke since the last calibration sample.
        private var trackingBroke = false
        /// The text of the stage's latest ERR reply ("LIMIT 0-180", ...).
        private var lastErrorText = ""
        private var restoreAsksEdges = true
        private var loop: Task<Void, Never>?
        private var waiter: (id: Int, accept: (StageReply) -> Bool?, done: (Bool) -> Void)?
        private var nextWaiterID = 0

        private let calibrationStepDegrees = 3
        private let settleSeconds = 0.3
        private let sampleSeconds = 0.4

        init(engine: SlideMovementLabModel) { self.engine = engine }

        // MARK: On / off

        func activate(restoringAsksEdges previous: Bool) {
            restoreAsksEdges = previous
            engine.setAsksEdges(true)
            client.onReply = { [weak self] reply in
                MainActor.assumeIsolated { self?.handle(reply) }
            }
            engine.onGuideSample = { [weak self] position, tracking, _ in
                MainActor.assumeIsolated { self?.sample(position, tracking) }
            }
            client.connect()
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    self?.tick()
                }
            }
        }

        func deactivate() {
            loop?.cancel()
            loop = nil
            if client.status == .connected { client.send(.stop) }
            engine.setAsksEdges(restoreAsksEdges)
            engine.onGuideSample = nil
            client.onReply = nil
            client.disconnect()
            finishWaiter(false)
        }

        // MARK: Buttons

        func pause() {
            userPaused = true
            client.send(.stop)
            inFlight = false
            phase = .paused
        }

        func resume() {
            userPaused = false
            if mapping != nil, phase == .paused { phase = .following }
        }

        func endSession() {
            userPaused = true
            client.send(.end)
            inFlight = false
            phase = .paused
        }

        /// After a failure, or to measure again at the stage step.
        func recalibrate() {
            mapping = nil
            mappingSummary = ""
            phase = .waitingForStageStep
        }

        // MARK: Replies and samples

        private func handle(_ reply: StageReply) {
            switch reply {
            case .position(let x, let y), .done(let x, let y), .resumed(let x, let y, _),
                .hello(_, _, let x, let y), .status(_, _, let x, let y, _):
                angleX = x
                angleY = y
            case .ok(let text) where text.hasPrefix("STOP"):
                // "OK STOP X=120 Y=90"
                for part in text.split(separator: " ") {
                    if part.hasPrefix("X="), let v = Int(part.dropFirst(2)) { angleX = v }
                    if part.hasPrefix("Y="), let v = Int(part.dropFirst(2)) { angleY = v }
                }
            default: break
            }
            switch reply {
            case .position, .done:
                inFlight = false
                lastSettledAt = Date()
            case .ok(let text) where text.hasPrefix("STOP"):
                inFlight = false
                lastSettledAt = Date()
            case .error(let text):
                inFlight = false
                lastErrorText = text
                if text.hasPrefix("LIMIT"), mapping != nil, !isCalibrating { phase = .atLimit(lastServo) }
            default: break
            }
            if let w = waiter, let result = w.accept(reply) { finishWaiter(result) }
        }

        /// Called for every analysed frame. Tracking that breaks between sampling windows (while a
        /// servo moves) still splits the calibration's runs.
        private func sample(_ position: CGPoint, _ tracking: TrackingState) {
            let tracked = tracking == .tracking
            if !tracked { trackingBroke = true }
            guard let c = collecting else { return }
            calibration.add(
                servo: c.servo, angle: c.angle, position: unstraightened(position),
                tracking: tracking, afterGap: tracked && trackingBroke)
            if tracked { trackingBroke = false }
        }

        /// The stage axes the preview is straightened by now (nil when it is not).
        private var straightening: CGAffineTransform? {
            guideIsStraightened ? engine.setupInfo.stageAxes?.straightening : nil
        }

        /// A guide-field vector back to the picture as the camera sees it, which the servo mapping
        /// is kept in: the preview (and so the guide) may be straightened by the stage's axes.
        private func unstraightened(_ v: CGPoint) -> CGPoint {
            guard let s = straightening else { return v }
            return v.applying(s.inverted().withoutTranslation)
        }

        /// Sends `command` and waits for a reply `accept` decides on (true: good, false: bad).
        private func request(
            _ command: StageCommand, timeout: Double = 10, accept: @escaping (StageReply) -> Bool?
        ) async -> Bool {
            await withCheckedContinuation { cont in
                nextWaiterID += 1
                let id = nextWaiterID
                waiter = (id, accept, { cont.resume(returning: $0) })
                if !client.send(command) {
                    finishWaiter(false)
                    return
                }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    if self?.waiter?.id == id { self?.finishWaiter(false) }
                }
            }
        }

        private func finishWaiter(_ result: Bool) {
            guard let w = waiter else { return }
            waiter = nil
            w.done(result)
        }

        private func goTo(_ servo: StageAxis, _ angle: Int) async -> Bool {
            inFlight = true
            let ok = await request(.goTo(servo, angle)) {
                if case .position = $0 { return true }
                if case .error = $0 { return false }
                return nil
            }
            inFlight = false
            return ok
        }

        // MARK: Calibration

        private func calibrate() async {
            isCalibrating = true
            defer { isCalibrating = false }
            calibration = StageAutoCalibration()
            let ready = await request(.mode(.manual)) {
                if case .ok = $0 { return true }
                if case .error = $0 { return false }
                return nil
            }
            guard ready,
                await request(
                    .home, timeout: 20,
                    accept: {
                        if case .done = $0 { return true }
                        if case .error = $0 { return false }
                        return nil
                    })
            else { return fail("The stage did not answer MODE MANUAL / HOME") }

            for servo in [StageAxis.x, .y] {
                let start = servo == .x ? angleX : angleY
                let direction = start <= 90 ? 1 : -1
                var current = start
                await collect(servo, current)
                while calibration.travel(of: servo) < calibration.minTravelFields,
                    abs(current - start) < calibration.maxDegrees,
                    (0...180).contains(current + direction * calibrationStepDegrees)
                {
                    current += direction * calibrationStepDegrees
                    lastErrorText = ""
                    guard await goTo(servo, current) else {
                        if lastErrorText.hasPrefix("LIMIT") {
                            // The firmware's saved range ends here: measure with what was covered.
                            current -= direction * calibrationStepDegrees
                            break
                        }
                        _ = await goTo(servo, start)
                        return fail("Servo \(servo.letter) did not move")
                    }
                    await collect(servo, current)
                    phase = .calibrating(axis: servo, travel: calibration.travel(of: servo))
                }
                _ = await goTo(servo, start)  // back to where it began
                try? await Task.sleep(for: .seconds(settleSeconds))
                if case .failure(let failure) = calibration.vector(for: servo) {
                    return fail(failure.localizedDescription)
                }
            }
            switch calibration.mapping() {
            case .failure(let failure): fail(failure.localizedDescription)
            case .success(let found):
                mapping = found
                mappingSummary = found.summary
                phase = .calibrated(summary: found.summary)
                engine.completeStage(with: found.axes)
            }
        }

        /// Lets the picture settle, then takes samples for a moment.
        private func collect(_ servo: StageAxis, _ angle: Int) async {
            try? await Task.sleep(for: .seconds(settleSeconds))
            collecting = (servo, Double(angle))
            try? await Task.sleep(for: .seconds(sampleSeconds))
            collecting = nil
        }

        private func fail(_ message: String) {
            collecting = nil
            phase = .failed(message)
        }

        // MARK: Following

        private func tick() {
            guard client.status == .connected else {
                if phase != .disconnected, !isCalibrating {
                    phase = .disconnected
                    inFlight = false
                    userPaused = userPaused || mapping != nil  // stay paused until Resume
                }
                return
            }
            let step = engine.setupInfo.step
            if phase == .disconnected {
                phase = mapping != nil && step == .done ? .paused : .waitingForStageStep
            }
            guard !isCalibrating else { return }
            if step != .done, step != .stage, mapping != nil {
                recalibrate()  // setup went back: the old measurement is stale
                return
            }
            if step == .stage || step == .done, mapping == nil, phase == .waitingForStageStep {
                phase = .calibrating(axis: .x, travel: 0)
                Task { await calibrate() }
                return
            }
            guard step == .done else { return }
            guard mapping != nil else { return }
            if case .calibrated = phase { phase = .following }
            if userPaused || phase == .paused { return }
            follow()
        }

        private func follow() {
            if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
                // The reply never came (or the move was to the angle it is already at).
                inFlight = false
                lastSettledAt = Date()
                client.send(.status)
                lastMove = "No reply, resynced"
            }
            if engine.overlayState.asksEdge {
                if inFlight {
                    client.send(.stop)
                    inFlight = false
                    lastSettledAt = Date()
                }
                phase = .waitingForEdgeAnswer
                return
            }
            if phase == .waitingForEdgeAnswer { phase = .following }
            let guideOff = "turn on Guide dry run"
            guard engine.guideInfo.isOn else {
                lastMove = guideOff
                return
            }
            if lastMove == guideOff { lastMove = "" }
            guard let mapping, !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3,
                let dx = engine.guideInfo.steerDx, let dy = engine.guideInfo.steerDy
            else { return }
            // The guide's axes may be the straightened picture's; the servos were measured raw.
            let target = unstraightened(CGPoint(x: dx, y: dy))
            var planner = StageMotionPlanner(mapping: mapping, chunkDegrees: chunkDegrees)
            planner.deadbandFields = 0.15
            switch planner.next(angles: (angleX, angleY), target: target) {
            case .idle: break
            case .atLimit(let servo):
                phase = .atLimit(servo)
            case .move(let servo, let angle):
                if client.send(.goTo(servo, angle)) {
                    inFlight = true
                    moveSentAt = Date()
                    lastServo = servo
                    lastMove = "GOTO \(servo.letter) \(angle)"
                    phase = .following
                }
            }
        }
    }

    extension CGAffineTransform {
        fileprivate var withoutTranslation: CGAffineTransform {
            CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
        }
    }
#endif
