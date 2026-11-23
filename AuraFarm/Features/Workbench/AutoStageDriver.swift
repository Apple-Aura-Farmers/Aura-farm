import CoreGraphics
import Foundation
import Observation

/// Drives the Terraloka stage from the slide movement lab: measures how each servo moves the
/// picture, hands the lab its stage axes, then follows the guide's target one small move at a
/// time. Edges are still confirmed by the person; the stage stops while one is asked.
///
/// Shared by the debug lab and the guided scan's Terraloka Stage flow (Release builds).
@MainActor
@Observable
final class AutoStageDriver {
    enum Phase: Equatable {
        case disconnected
        case waitingForStageStep
        case warmingUp(index: Int, count: Int, title: String)
        case calibrating(axis: StageAxis, travel: Double)
        case calibrated(summary: String)
        /// Calibrated, and held until `beginRun()` (see `requiresRunStart`).
        case readyToStart
        case following
        case waitingForEdgeAnswer
        case atLimit(StageAxis)
        /// After a stage restart: moving the servos back to where they were.
        case walkingBack(x: Int, y: Int)
        case crossingEmpty(fields: Double)
        case emptyCapReached(fields: Double)
        case presetPath(column: Int, spot: Int)
        case paused
        case failed(String)
    }

    let client = StageBLEClient()
    private(set) var phase = Phase.disconnected
    private(set) var lastMove = ""
    private(set) var mappingSummary = ""
    var chunkDegrees = 3
    /// The objective in use; set before `activate`. The step size starts at its default.
    var objective = StageObjective.x40
    /// What runs before calibration, so the linkage is past its slack and stick-slip. Empty
    /// for no warm-up.
    var warmUpSequence = StageWarmUpItem.defaultSequence
    /// The guided scan holds the stage after calibration until the person taps Start scan
    /// (`beginRun()`); the lab does not.
    var requiresRunStart = false
    /// Called once when something needs the person; the lab leaves it nil.
    var alertSink: ((AutoStageAlert) -> Void)?
    /// A finished guide (its run summary exists) ends the stage session, like the preset
    /// path's natural finish does.
    var autoEndsOnGuideFinish = false
    /// Whether the guide asks the person about edges while the stage runs (the lab); off in
    /// the Terraloka test, where the stage decides.
    var asksEdgeQuestions = true
    /// The preset path is standing at a spot.
    var isDwelling: Bool { dwellUntil != nil }
    /// How the stage moves once setup is done; set before `activate`.
    var pathMode = StagePathMode.followGuide
    /// How long the preset path stays at each spot, in seconds.
    var dwellSeconds = 1.2
    /// The preset path asks before ending a leg at an edge (the lab's "Ask me to confirm edges").
    private(set) var presetEdgePrompt = false
    /// Press the guide's "Stage limit" when a servo is pinned at 0 or 180.
    var autoStageLimit = true
    private(set) var autoStageLimitCount = 0
    /// The lab shows the picture straightened (and so measures the guide in straightened axes).
    var guideIsStraightened = true

    private let engine: ScanEngine
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
    private var limitPress = StageLimitAutoPress()
    private var stallWatch = StageStallWatch()
    private var mappingWatch = StageMappingWatch()
    private var stuckWatch = StageStuckWatch()
    private var runBegun = false
    private var sessionEnded = false
    private var hasConnected = false
    private var lastAlertKind: String?
    // A stage restart: where the servos and the tracker were when the link dropped.
    private var savedAngles: (x: Int, y: Int)?
    private var savedTrackerPosition: CGPoint?
    private var walkBack: (angles: (x: Int, y: Int), tracker: CGPoint)?
    /// Shown in the panel after the stage restarted, until Resume has walked it back.
    private(set) var restartNotice: String?
    /// The move being checked against the mapping: where the picture was when it was sent.
    private var moveCheck:
        (
            servo: StageAxis, from: Int, before: CGPoint, lost: Bool, posAt: Date?,
            detailBefore: Bool
        )?
    /// The latest tracked guide position (raw), and when it was seen.
    private var lastTracked: (position: CGPoint, at: Date)?
    // The preset zig-zag.
    private var zigzag: StageZigzag?
    private var presetEvent: StageZigzagEvent?
    private var presetAwaitingSettle = false
    private var presetFinished = false
    private var dwellUntil: Date?
    private var countingColumn: Int?
    private var sawSampleInColumn = false
    private var noSampleSince: Date?
    private var ignoreEdgeThisLeg = false
    /// Since when the leg servo could not move while a cross-axis servo is pinned.
    private var crossStuckSince: Date?
    /// The last direction the guide steered in (raw guide fields), for crossing blind.
    private var lastSteer: CGPoint?
    private var crossing: StageBlindCrossing?
    private var crossingLogged = false
    private var trackingNow = TrackingState.lost
    /// How far the current crossing may go before the person is asked, in fields.
    private(set) var blindCap = 2.0
    /// A move was sent since the last stall check.
    private var movedForStall = false
    /// Tracking has been lost since this time; nil while it is not.
    private var lostSince: Date?
    private var lastReanchorAt = Date.distantPast
    private var movedSinceLastPress = false
    /// Pause, End session or leaving stops the warm-up and calibration between moves.
    private var cancelSweep = false
    /// Tracking broke since the last calibration sample.
    private var trackingBroke = false
    /// The text of the stage's latest ERR reply ("LIMIT 0-180", ...).
    private var lastErrorText = ""
    private var restoreAsksEdges = true
    private var loop: Task<Void, Never>?
    private var waiter: (id: Int, accept: (StageReply) -> Bool?, done: (Bool) -> Void)?
    private var nextWaiterID = 0

    /// Calibration and the lab stage step move in the chosen chunk (at most 3 degrees): at
    /// 100x one 3-degree step jumps the picture further than the tracker can follow.
    private var calibrationStepDegrees: Int {
        max(objective.minChunk, min(chunkDegrees, 3))
    }
    private let settleSeconds = 0.3
    private let sampleSeconds = 0.4

    init(engine: ScanEngine) { self.engine = engine }

    // MARK: On / off

    func activate(restoringAsksEdges previous: Bool) {
        restoreAsksEdges = previous
        engine.setAsksEdges(asksEdgeQuestions)
        sessionEnded = false
        engine.logEvent("objective_\(objective.title)")
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
        cancelSweep = true
        engine.setExternalCounting(active: false, column: 0)
        if client.status == .connected { client.send(.stop) }
        engine.setAsksEdges(restoreAsksEdges)
        engine.onGuideSample = nil
        engine.setStageAngles(nil)
        client.onReply = nil
        client.disconnect()
        finishWaiter(false)
    }

    // MARK: Buttons

    func pause() {
        if crossing != nil { finishCrossing("blind_cross_paused") }
        userPaused = true
        cancelSweep = true
        finishWaiter(false)  // a warm-up or calibration wait ends now, not at its timeout
        client.send(.stop)
        inFlight = false
        engine.setExternalCounting(active: false, column: 0)
        phase = .paused
    }

    func resume() {
        userPaused = false
        guard phase == .paused else { return }
        sessionEnded = false
        guard mapping != nil else {
            phase = .waitingForStageStep
            return
        }
        if let walkBack {
            // The stage restarted: counting stays off until the servos are back.
            phase = .walkingBack(x: walkBack.angles.x, y: walkBack.angles.y)
            return
        }
        if requiresRunStart, !runBegun {
            phase = .readyToStart
            return
        }
        resumeWhereItStopped()
    }

    private func resumeWhereItStopped() {
        // Walked back (or resumed) before Start scan: still no move until the run starts.
        if requiresRunStart, !runBegun {
            phase = .readyToStart
            return
        }
        if pathMode == .presetPath {
            // A move that was stopped counts as settled where it stopped.
            if presetAwaitingSettle {
                presetAwaitingSettle = false
                presetEvent = .settled
            }
            if let countingColumn { engine.setExternalCounting(active: true, column: countingColumn) }
            phase = .presetPath(column: zigzag?.column ?? 0, spot: zigzag?.spot ?? 0)
        } else {
            phase = .following
        }
    }

    // MARK: A restarted stage

    /// The first HELLO / STATUS after a drop: angles more than a degree from where the servos
    /// were mean the stage lost power and started again (its servos jump to 90).
    private func checkForRestart(reported: (x: Int, y: Int)) {
        guard let saved = savedAngles, let tracker = savedTrackerPosition else { return }
        savedAngles = nil
        savedTrackerPosition = nil
        guard StageRestart.detected(saved: saved, reported: reported) else { return }  // a plain drop
        walkBack = (saved, tracker)
        restartNotice =
            "The stage restarted (check its power). Resume walks it back to \(saved.x),\(saved.y)."
        engine.logEvent(
            "stage_restart_detected",
            detail: "saved \(saved.x),\(saved.y) reported \(reported.x),\(reported.y)")
    }

    /// Walks the servos back to the saved angles, Y first, in panel-sized steps; then the
    /// tracker's position is put back and the path or the guide goes on where it was.
    private func walkBackStep() {
        guard let walkBack else { return resumeWhereItStopped() }
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
        }
        guard !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3 else { return }
        guard
            let next = StageRestart.nextStep(
                from: (angleX, angleY), to: walkBack.angles, chunk: chunkDegrees)
        else {
            engine.restoreTrackerPosition(to: walkBack.tracker)
            engine.logEvent(
                "stage_restart_walked_back", detail: "\(walkBack.angles.x),\(walkBack.angles.y)")
            self.walkBack = nil
            restartNotice = nil
            lastMove = "Walked back after the restart"
            resumeWhereItStopped()
            return
        }
        moveCheck = nil  // these moves say nothing about the mapping
        guard client.send(.goTo(next.servo, next.angle)) else { return }
        inFlight = true
        moveSentAt = Date()
        lastServo = next.servo
        lastMove = "GOTO \(next.servo.letter) \(next.angle) (walk back)"
    }

    /// Opens the run gate: the stage starts following the guide or the preset path.
    func beginRun() {
        runBegun = true
        sessionEnded = false
        userPaused = false
        guard mapping != nil else {
            // Paused during the warm-up or calibration: measure again; the open gate then
            // starts the run.
            if phase == .paused { phase = .waitingForStageStep }
            return
        }
        switch phase {
        case .readyToStart, .calibrated, .paused:
            phase = pathMode == .presetPath ? .presetPath(column: 0, spot: 0) : .following
            if pathMode == .followGuide {
                engine.logEvent("stage_mapping", detail: mappingSummary)
            }
        default: break
        }
    }

    /// Only while paused or before setup is done (the panel enforces it).
    func setPathMode(_ new: StagePathMode) {
        guard new != pathMode else { return }
        pathMode = new
        zigzag = nil
        presetFinished = false
        presetEvent = nil
        presetAwaitingSettle = false
        dwellUntil = nil
        presetEdgePrompt = false
        countingColumn = nil
        engine.setExternalCounting(active: false, column: 0)
        engine.logEvent("path_mode_\(new.rawValue)")
    }

    func endSession() {
        guard !sessionEnded else { return }
        sessionEnded = true
        userPaused = true
        cancelSweep = true
        finishWaiter(false)
        client.send(.end)
        inFlight = false
        engine.setExternalCounting(active: false, column: 0)
        phase = .paused
    }

    /// A measurement taken at the other magnification is wrong: it is made again.
    func changeObjective(to new: StageObjective) {
        objective = new
        chunkDegrees = max(new.defaultChunk, new.minChunk)
        engine.logEvent("objective_\(new.title)")
        if mapping != nil { recalibrate() }
    }

    /// After a failure, or to measure again at the stage step.
    func recalibrate() {
        runBegun = false  // a new test: the run gate closes again
        sessionEnded = false  // and its END is sent again when it ends
        walkBack = nil
        restartNotice = nil
        mapping = nil
        mappingSummary = ""
        phase = .waitingForStageStep
    }

    // MARK: Crossing an empty patch

    /// The focus-pause banner may offer "In focus – empty area".
    var canConfirmEmptyArea: Bool {
        phase == .following && mapping != nil && pathMode == .followGuide
    }

    /// The person says the view is in focus: it is an empty patch. Cross it blind.
    func confirmEmptyArea() {
        guard canConfirmEmptyArea else { return }
        guard let lastSteer, hypot(Double(lastSteer.x), Double(lastSteer.y)) > 0 else {
            lastMove = "No direction to cross in"
            return
        }
        engine.resumeFocusAnyway()
        engine.logEvent("empty_confirmed")
        crossing = StageBlindCrossing(
            direction: lastSteer, startAngles: (angleX, angleY))
        blindCap = crossing?.capFields ?? 2.0
        crossingLogged = false
        phase = .crossingEmpty(fields: 0)
    }

    /// "End column here" after a crossing that stayed empty.
    func endColumnHere() {
        guard crossing != nil else { return }
        // The crossed distance first: the tracker adds it on the next frame, before the guide
        // reads the limit on that same frame, so the column ends where the stage is.
        finishCrossing("blind_cross_end")
        engine.stageLimit(cause: .blindEdge)
    }

    /// "Keep going": the cap grows and the crossing continues.
    func keepCrossing() {
        guard crossing != nil else { return }
        crossing?.extendCap()
        blindCap = crossing?.capFields ?? blindCap
        phase = .crossingEmpty(fields: crossedFields)
    }

    private var crossedFields: Double {
        guard let crossing, let mapping else { return 0 }
        return crossing.distance(angles: (angleX, angleY), mapping: mapping)
    }

    /// Ends the crossing: the distance crossed goes to the tracker, which jumps there at the
    /// next frame with detail, and the focus baseline is measured again.
    private func finishCrossing(_ event: String) {
        guard let crossing, let mapping else { return }
        let moved = crossing.movedFields(angles: (angleX, angleY), mapping: mapping)
        // The guide's axes may be the straightened picture's: the inverse of `unstraightened`.
        let guideFields = straightening.map { moved.applying($0.withoutTranslation) } ?? moved
        engine.addBlindMove(guideFields: guideFields)
        engine.logEvent(event, detail: String(format: "%.2f fields", crossedFields))
        engine.requestFocusBaselineRemeasure()
        self.crossing = nil
        stallWatch = StageStallWatch()
        phase = .following
    }

    private func crossStep() {
        guard let current = crossing, let mapping else { return }
        if engine.overlayState.asksEdge {
            if inFlight {
                client.send(.stop)
                inFlight = false
                lastSettledAt = Date()
            }
            finishCrossing("blind_cross_edge_question")
            phase = .waitingForEdgeAnswer
            return
        }
        guard !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3 else { return }
        let angles = (angleX, angleY)
        if trackingNow == .tracking, !engine.guideInfo.holdsForPicture {
            return finishCrossing("blind_cross_end")  // detail is back
        }
        if case .emptyCapReached = phase { return }  // waiting for the person's choice
        if current.reachedCap(angles: angles, mapping: mapping) {
            phase = .emptyCapReached(fields: crossedFields)
            return
        }
        var planner = makePlanner(mapping)
        planner.deadbandFields = 0.15
        switch planner.next(angles: angles, target: current.target()) {
        case .idle: break
        case .atLimit:
            phase = .emptyCapReached(fields: crossedFields)
        case .move(let servo, let angle):
            if !crossingLogged {
                crossingLogged = true
                engine.logEvent("blind_cross_start")
            }
            if sendMove(servo, angle) {
                inFlight = true
                moveSentAt = Date()
                lastServo = servo
                lastMove = "GOTO \(servo.letter) \(angle) (blind)"
                phase = .crossingEmpty(fields: crossedFields)
            }
        }
    }

    // MARK: Replies and samples

    private func handle(_ reply: StageReply) {
        switch reply {
        case .position(let x, let y), .done(let x, let y), .resumed(let x, let y, _),
            .hello(_, _, let x, let y), .status(_, _, let x, let y, _):
            if case .hello = reply { checkForRestart(reported: (x, y)) }
            if case .status = reply { checkForRestart(reported: (x, y)) }
            angleX = x
            angleY = y
            engine.setStageAngles((x, y))
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
            // Every step starts from zero offset: a step can move the picture further than the
            // tracker trusts between two frames.
            engine.requestTrackerReanchor()
            if moveCheck != nil, moveCheck?.posAt == nil { moveCheck?.posAt = Date() }
            if presetAwaitingSettle, zigzag != nil {
                presetAwaitingSettle = false
                presetEvent = .settled
            }
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
        trackingNow = tracking
        if tracking == .lost { lostSince = lostSince ?? Date() } else { lostSince = nil }
        // Only a real loss splits the calibration's runs; the brief paused / matching frames
        // of motion blur at 100x do not (and add no sample).
        if tracking == .lost {
            trackingBroke = true
            moveCheck?.lost = true
        }
        if tracked { lastTracked = (unstraightened(position), Date()) }
        guard let c = collecting, tracked || tracking == .lost else { return }
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
        // The firmware drops a move to where the servo already is without a reply.
        if (servo == .x ? angleX : angleY) == angle { return true }
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
        cancelSweep = false
        defer { isCalibrating = false }
        calibration = StageAutoCalibration()
        stuckWatch = StageStuckWatch()
        // A warm-up path stopped part-way (Pause, Close, a closed app) stays queued in AUTO, and
        // MODE then answers BUSY. HOME clears it and starts from a known place.
        let homed = await request(
            .home, timeout: 20,
            accept: {
                if case .done = $0 { return true }
                if case .error = $0 { return false }
                return nil
            })
        if sweepStopped { return stopSweep() }
        guard homed else { return fail("The stage did not answer HOME") }
        for (index, item) in warmUpSequence.enumerated() {
            await warmUpStage(item, index: index + 1, of: warmUpSequence.count)
            if sweepStopped { return stopSweep() }
        }
        let ready = await request(.mode(.manual)) {
            if case .ok = $0 { return true }
            if case .error = $0 { return false }
            return nil
        }
        if sweepStopped { return stopSweep() }
        guard ready,
            await request(
                .home, timeout: 20,
                accept: {
                    if case .done = $0 { return true }
                    if case .error = $0 { return false }
                    return nil
                })
        else {
            if sweepStopped { return stopSweep() }
            return fail("The stage did not answer MODE MANUAL / HOME")
        }

        for servo in [StageAxis.x, .y] {
            if sweepStopped { return stopSweep() }
            guard await sweepServo(servo) else { return }
        }
        if sweepStopped { return stopSweep() }
        // Both servos drive one actuator: one far weaker than the other is a slipped tracker.
        // Measure that servo once more before giving up.
        if case .success(let vx) = calibration.vector(for: .x),
            case .success(let vy) = calibration.vector(for: .y),
            let weak = StageAutoCalibration.weakServo(x: vx, y: vy)
        {
            calibration.discard(weak.servo)
            guard await sweepServo(weak.servo) else { return }
            if sweepStopped { return stopSweep() }
            var now = 0.0
            if case .success(let v) = calibration.vector(for: weak.servo) {
                now = hypot(Double(v.x), Double(v.y))
            }
            engine.logEvent(
                "calibration_recheck",
                detail: String(
                    format: "servo %@ old=%.4f new=%.4f f/deg", weak.servo.letter, weak.weak, now))
        }
        switch calibration.mapping() {
        case .failure(let failure):
            if case .scaleMismatch = failure {
                engine.logEvent("calibration_ratio_failed", detail: failure.localizedDescription)
            }
            fail(failure.localizedDescription)
        case .success(let found):
            mapping = found
            mappingSummary = found.summary
            if engine.setupInfo.step == .stage {
                // The servos measured the axes: the lab's own tilt step is not needed.
                engine.completeStage(with: found.axes)
                engine.logEvent(
                    "stage_step_skipped",
                    detail: String(
                        format: "automated stage axes: tilt %.1f° skew %.1f°",
                        found.axes.tiltDegrees, found.axes.skewDegrees))
                mappingSummary += " (lab tilt step skipped: automated stage axes)"
            }
            phase = .calibrated(summary: mappingSummary)
        }
    }

    /// Turns one servo from where it is until the picture has moved enough, and back to where it
    /// began; false when it could not be measured (the phase set to failed) or was stopped
    /// (Pause, End session, a drop: the phase set to paused, no further move).
    private func sweepServo(_ servo: StageAxis) async -> Bool {
        let start = servo == .x ? angleX : angleY
        let direction = start <= 90 ? 1 : -1
        var current = start
        await collect(servo, current)
        if sweepStopped {
            stopSweep()
            return false
        }
        while calibration.travel(of: servo) < calibration.minTravelFields
            || calibration.movingAngles(of: servo) < 5,
            abs(current - start) < calibration.maxDegrees,
            (0...180).contains(current + direction * calibrationStepDegrees)
        {
            current += direction * calibrationStepDegrees
            lastErrorText = ""
            guard await goTo(servo, current) else {
                if sweepStopped {
                    stopSweep()
                    return false
                }
                if lastErrorText.hasPrefix("LIMIT") {
                    // The firmware's saved range ends here: measure with what was covered.
                    current -= direction * calibrationStepDegrees
                    break
                }
                _ = await goTo(servo, start)
                fail("Servo \(servo.letter) did not move")
                return false
            }
            await collect(servo, current)
            if sweepStopped {
                stopSweep()
                return false
            }
            phase = .calibrating(axis: servo, travel: calibration.travel(of: servo))
        }
        // Back to where it began, in the same steps, so the tracker follows the picture
        // there (one big jump loses it, and the next servo's samples start from a wrong
        // position).
        while current != start {
            if sweepStopped {
                stopSweep()
                return false
            }
            let back = current - direction * calibrationStepDegrees
            current = direction > 0 ? max(back, start) : min(back, start)
            guard await goTo(servo, current) else { break }
        }
        try? await Task.sleep(for: .seconds(settleSeconds))
        if sweepStopped {
            stopSweep()
            return false
        }
        if case .failure(let failure) = calibration.vector(for: servo) {
            fail(failure.localizedDescription)
            return false
        }

        return true
    }

    /// Runs one warm-up item in AUTO to take up the linkage's slack before calibrating. A
    /// timeout or an ERR is logged and the next item carries on.
    private func warmUpStage(_ item: StageWarmUpItem, index: Int, of count: Int) async {
        phase = .warmingUp(index: index, count: count, title: item.title)
        engine.logEvent("warmup_start", detail: item.title)
        func answered(_ reply: StageReply, ok: (String) -> Bool) -> Bool? {
            if case .ok(let text) = reply { return ok(text) ? true : nil }
            if case .error = reply { return false }
            return nil
        }
        func done(_ reply: StageReply) -> Bool? {
            if case .done = reply { return true }
            if case .error = reply { return false }
            return nil
        }
        lastErrorText = ""
        var finished = false
        guard await request(.mode(.auto), accept: { answered($0) { $0.hasPrefix("MODE") } })
        else {
            return warmUpFailed(item, "no answer to MODE AUTO")
        }
        if sweepStopped {
            client.send(.stop)
            return
        }
        switch item {
        case .traverse:
            // Full X and Y sweeps at 2° per 20 ms, plus the rests between them.
            finished = await request(.traverse, timeout: 40, accept: done)
        case .preset(let preset):
            if await request(
                .path(preset.points), accept: { answered($0) { $0.hasPrefix("PATH") } }),
                !sweepStopped
            {
                finished = await request(.start, timeout: 90, accept: done)
            }
        }
        if sweepStopped {
            client.send(.stop)
            return
        }
        if finished {
            engine.logEvent("warmup_done", detail: item.title)
        } else {
            warmUpFailed(item, lastErrorText.isEmpty ? "timed out" : lastErrorText)
        }
    }

    private func warmUpFailed(_ item: StageWarmUpItem, _ reason: String) {
        client.send(.stop)
        engine.logEvent("warmup_failed", detail: "\(item.title): \(reason)")
    }

    // MARK: Stopping a measurement

    private var sweepStopped: Bool { cancelSweep || client.status != .connected }

    /// Pause / End session / disconnect during the warm-up or calibration: measure again on Resume.
    private func stopSweep() {
        collecting = nil
        mapping = nil
        mappingSummary = ""
        if !userPaused, client.status == .connected {
            // Resume was tapped while this measurement wound down: the next one starts.
            phase = .waitingForStageStep
        } else if phase != .paused, phase != .disconnected {
            phase = .paused
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
        if client.status == .connected { hasConnected = true }
        updateAlert()
        guard client.status == .connected else {
            if phase != .disconnected, !isCalibrating {
                // The last position before the drop, to tell a restart from a plain drop.
                if mapping != nil, savedAngles == nil, walkBack == nil {
                    savedAngles = (angleX, angleY)
                    savedTrackerPosition = engine.trackerPosition()
                }
                phase = .disconnected
                inFlight = false
                userPaused = userPaused || mapping != nil  // stay paused until Resume
            }
            return
        }
        reanchorIfStuckLost()
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
        evaluateMoveCheck(force: false)
        if autoEndsOnGuideFinish, runBegun, engine.runSummary != nil {
            endSession()  // the guide finished and its summary exists
            return
        }
        if case .calibrated = phase {
            if requiresRunStart, !runBegun {
                phase = .readyToStart
            } else {
                phase = pathMode == .presetPath ? .presetPath(column: 0, spot: 0) : .following
                if pathMode == .followGuide {
                    engine.logEvent("stage_mapping", detail: mappingSummary)
                }
            }
        }
        if case .readyToStart = phase { return }  // no move before the run starts
        if userPaused || phase == .paused { return }
        if case .walkingBack = phase {
            walkBackStep()
            return
        }
        if let zigzag {
            self.zigzag?.boostLeg = stuckWatch.extraDegrees(for: zigzag.plan.legServo)
            self.zigzag?.boostStep = stuckWatch.extraDegrees(for: zigzag.plan.stepServo)
        }
        if pathMode == .presetPath { presetStep() } else { follow() }
    }

    /// The plain-words status, for the guided scan's screens.
    var status: AutoStageStatus {
        AutoStageStatus.make(
            phase: phase, restartNotice: restartNotice, presetEdgePrompt: presetEdgePrompt,
            pathMode: pathMode, client: client.status, focusPaused: isFocusPaused,
            dwelling: isDwelling, hasConnected: hasConnected)
    }

    private var isFocusPaused: Bool {
        engine.setupInfo.step == .done && engine.setupInfo.monitor.state == .pausedFocus
    }

    /// Tells the alert sink once each time something needs the person.
    private func updateAlert() {
        let alert = status.needsPerson
        guard alert?.kind != lastAlertKind else { return }
        lastAlertKind = alert?.kind
        guard let alert else { return }
        engine.logEvent("alert_\(alert.kind)")
        alertSink?(alert)
    }

    /// Tracking lost for a while with the stage still: anchor again where it is.
    private func reanchorIfStuckLost() {
        let now = Date()
        guard let lostSince, now.timeIntervalSince(lostSince) >= 1.5, !inFlight,
            now.timeIntervalSince(lastSettledAt) >= 1,
            now.timeIntervalSince(lastReanchorAt) >= 2
        else { return }
        lastReanchorAt = now
        engine.requestTrackerReanchor()
    }

    // MARK: The preset path

    /// "Edge here" on the preset path's edge prompt.
    func edgeHere() {
        presetEdgePrompt = false
        applyPresetEdge()
    }

    /// "Keep going" on the edge prompt: no edge on this leg.
    func keepGoingPastEdge() {
        presetEdgePrompt = false
        ignoreEdgeThisLeg = true
        if presetAwaitingSettle {  // the move that was stopped counts as done
            presetAwaitingSettle = false
            presetEvent = .settled
        }
    }

    private func applyPresetEdge() {
        noSampleSince = nil
        sawSampleInColumn = false
        if inFlight {
            client.send(.stop)
            inFlight = false
            lastSettledAt = Date()
        }
        presetAwaitingSettle = false
        dwellUntil = nil
        presetEvent = .edge
        if let plan = zigzag?.plan {
            let angle = plan.legServo == .x ? angleX : angleY
            engine.logEvent(
                "preset_path_edge", detail: "servo \(plan.legServo.letter) angle \(angle)")
        }
    }

    private func startPreset(_ mapping: StageServoMapping) {
        guard let plan = StageZigzagPlan(mapping: mapping) else {
            phase = .failed("Preset path: the servos do not move the picture")
            return
        }
        let zigzag = StageZigzag(
            plan: plan, chunkDegrees: chunkDegrees, dwellSeconds: dwellSeconds)
        self.zigzag = zigzag
        presetFinished = false
        engine.logEvent("stage_mapping", detail: mappingSummary)
        Task {
            // Another row, so the two events do not overwrite each other.
            try? await Task.sleep(for: .milliseconds(300))
            engine.logEvent("preset_path_start", detail: zigzag.summary)
        }
    }

    /// Looks for the end of the sample along a leg: blank (not blurry) for 0.6 s after the
    /// column showed sample.
    private func watchPresetEdge() {
        guard (zigzag?.column ?? 0) > 0, !ignoreEdgeThisLeg, !presetEdgePrompt else { return }
        let viewClass = engine.guideInfo.viewClass
        if viewClass == "sample" || viewClass == "thin" {
            sawSampleInColumn = true
            noSampleSince = nil
            return
        }
        let blank =
            viewClass == "blank"
            || (engine.guideInfo.holdsForPicture && trackingNow == .paused
                && viewClass != "blurry")
        guard sawSampleInColumn, blank else {
            noSampleSince = nil
            return
        }
        let since = noSampleSince ?? Date()
        noSampleSince = since
        guard Date().timeIntervalSince(since) >= 0.6 else { return }
        noSampleSince = nil
        if restoreAsksEdges {
            presetEdgePrompt = true
            if inFlight {
                client.send(.stop)
                inFlight = false
                lastSettledAt = Date()
            }
        } else {
            applyPresetEdge()
        }
    }

    private func presetStep() {
        guard let mapping else { return }
        if zigzag == nil {
            guard !presetFinished else { return }
            startPreset(mapping)
        }
        guard zigzag != nil else { return }
        zigzag?.dwellSeconds = dwellSeconds
        zigzag?.mapping = mapping
        zigzag?.chunkDegrees = max(chunkDegrees, 1)
        phase = .presetPath(column: zigzag?.column ?? 0, spot: zigzag?.spot ?? 0)
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
            if presetAwaitingSettle {
                presetAwaitingSettle = false
                presetEvent = .settled
            }
        }
        // A blurry view is the stall rule's (a focus pause), not an edge.
        let monitor = engine.setupInfo.monitor
        if stallWatch.update(
            now: Date(), holds: engine.guideInfo.holdsForPicture, moved: movedForStall,
            focusIndex: monitor.focusIndex, baseline: monitor.focusBaseline)
        {
            engine.requestFocusPause()
            lastMove = "Focus pause (stall)"
        }
        movedForStall = false
        guard monitor.state == .ok else { return }
        watchPresetEdge()
        guard !presetEdgePrompt else { return }
        if let until = dwellUntil {
            guard Date() >= until else { return }
            dwellUntil = nil
            presetEvent = .dwellDone
        }
        guard !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3 else { return }
        for _ in 0..<6 {
            let event = presetEvent
            presetEvent = nil
            var trackedPosition: CGPoint?
            if trackingNow == .tracking, let seen = lastTracked,
                Date().timeIntervalSince(seen.at) < 0.5
            {
                trackedPosition = seen.position
            }
            guard
                let action = zigzag?.next(
                    angles: (angleX, angleY), event: event, tracked: trackedPosition)
            else {
                return
            }
            switch action {
            case .moveTo(let servo, let angle):
                if sendMove(servo, angle) {
                    inFlight = true
                    moveSentAt = Date()
                    movedForStall = true
                    presetAwaitingSettle = true
                    lastServo = servo
                    lastMove = "GOTO \(servo.letter) \(angle) (preset)"
                } else {
                    presetEvent = event  // not sent: try again next tick
                }
                return
            case .dwell(let seconds):
                dwellUntil = Date().addingTimeInterval(seconds)
                let detail = "column \(zigzag?.column ?? 0) at \(angleX),\(angleY)"
                Task {
                    // Another row than preset_path_column, so they do not overwrite each other.
                    try? await Task.sleep(for: .milliseconds(300))
                    engine.logEvent("preset_path_stop", detail: detail)
                }
                return
            case .columnStarted(let column):
                ignoreEdgeThisLeg = false
                sawSampleInColumn = false
                noSampleSince = nil
                countingColumn = column
                engine.setExternalCounting(active: true, column: column)
                engine.logEvent("preset_path_column", detail: "\(column) at \(angleX),\(angleY)")
            case .swapped(let dx, let dy):
                // The path starts again from the new corner: drop what belonged to the old one.
                dwellUntil = nil
                engine.logEvent(
                    "preset_path_swapped", detail: String(format: "dx=%.2f dy=%.2f", dx, dy))
            case .columnEnded(let column):
                countingColumn = nil
                engine.setExternalCounting(active: false, column: column)
            case .finished(let reason):
                presetFinished = true
                zigzag = nil
                countingColumn = nil
                engine.setExternalCounting(active: false, column: 0)
                engine.logEvent("preset_path_done", detail: reason)
                lastMove = "Preset path done: \(reason)"
                userPaused = true
                phase = .paused
                // A natural finish ends the analysis session like the lab's "End now" (CSV,
                // summary, run JSON, map) and sends END to the stage. Later than the event
                // above, so the two do not share a CSV row.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    engine.endRun(.now)
                    endSession()
                }
                return
            }
        }
    }

    // MARK: Checking the mapping against what the picture did

    /// Sends a move and starts checking it: where the picture is now is "before", and what it
    /// shows after the move settled says whether the mapping's direction and size are right.
    private func sendMove(_ servo: StageAxis, _ angle: Int) -> Bool {
        evaluateMoveCheck(force: true)
        guard client.send(.goTo(servo, angle)) else { return false }
        moveCheck = nil
        if trackingNow == .tracking, let seen = lastTracked,
            Date().timeIntervalSince(seen.at) < 0.5
        {
            moveCheck = (
                servo, servo == .x ? angleX : angleY, seen.position, false, nil, hasDetailNow
            )
        }
        return true
    }

    private func makePlanner(_ mapping: StageServoMapping) -> StageMotionPlanner {
        var planner = StageMotionPlanner(mapping: mapping, chunkDegrees: chunkDegrees)
        planner.boostX = stuckWatch.extraDegrees(for: .x)
        planner.boostY = stuckWatch.extraDegrees(for: .y)
        return planner
    }

    /// The view shows sample or thin while tracking.
    private var hasDetailNow: Bool {
        let viewClass = engine.guideInfo.viewClass
        return trackingNow == .tracking && (viewClass == "sample" || viewClass == "thin")
    }

    /// CSV events one row apart, so none overwrites another logged in the same moment.
    private func logSpaced(_ events: [(name: String, detail: String)]) {
        guard !events.isEmpty else { return }
        Task {
            for (index, event) in events.enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(300)) }
                engine.logEvent(event.name, detail: event.detail)
            }
        }
    }

    /// A settled move is judged 0.4 s after its POS, or when the next move is sent.
    private func evaluateMoveCheck(force: Bool) {
        guard let check = moveCheck, let posAt = check.posAt else { return }
        guard force || Date().timeIntervalSince(posAt) >= 0.4 else { return }
        moveCheck = nil
        guard !check.lost, let after = lastTracked, after.at >= posAt, let mapping else { return }
        let degrees = Double((check.servo == .x ? angleX : angleY) - check.from)
        let delta = CGPoint(
            x: after.position.x - check.before.x, y: after.position.y - check.before.y)
        // A gear that did not answer says nothing about the fields per degree: it is judged
        // first and its move never reaches the mapping watch.
        let vector = check.servo == .x ? mapping.x : mapping.y
        let expected = hypot(Double(vector.x), Double(vector.y)) * abs(degrees)
        let seen = hypot(Double(delta.x), Double(delta.y))
        let outcome = stuckWatch.record(
            servo: check.servo, seen: seen, expected: expected,
            detailBefore: check.detailBefore, detailAfter: hasDetailNow)
        var events: [(name: String, detail: String)] = []
        if outcome.noResponse {
            events.append(
                (
                    "move_no_response",
                    String(
                        format: "servo %@ %+.0f° expected=%.3f seen=%.3f", check.servo.letter,
                        degrees, expected, seen)
                ))
        }
        if outcome.boostOn {
            events.append(("step_boost_on", "servo \(check.servo.letter)"))
        }
        if let reason = outcome.boostOff {
            events.append(("step_boost_off", "servo \(check.servo.letter) \(reason.rawValue)"))
        }
        logSpaced(events)
        if outcome.noResponse { return }
        if let fix = mappingWatch.record(
            servo: check.servo, degrees: degrees, delta: delta, mapping: mapping)
        {
            apply(fix)
        }
    }

    private func apply(_ fix: StageMappingCorrection) {
        guard let old = mapping else { return }
        let servo: StageAxis
        let vector: CGPoint
        let flipped: Bool
        switch fix {
        case .flip(let s, let v): (servo, vector, flipped) = (s, v, true)
        case .scale(let s, let v): (servo, vector, flipped) = (s, v, false)
        }
        guard
            case .success(let new) = StageAutoCalibration.servoMapping(
                x: servo == .x ? vector : old.x, y: servo == .y ? vector : old.y,
                xSlack: old.xSlackDegrees, ySlack: old.ySlackDegrees)
        else { return }
        let before = servo == .x ? old.x : old.y
        mapping = new
        zigzag?.mapping = new
        zigzag?.setFieldsPerDegree(
            x: hypot(Double(new.x.x), Double(new.x.y)),
            y: hypot(Double(new.y.x), Double(new.y.y)))
        mappingSummary =
            new.summary + (flipped ? " (direction corrected)" : " (step size re-measured)")
        lastMove =
            flipped
            ? "Direction corrected (servo \(servo.letter))"
            : "Step size re-measured (servo \(servo.letter))"
        engine.logEvent(
            flipped ? "mapping_flip" : "mapping_scale",
            detail: String(
                format: "servo %@ old=%.4f new=%.4f f/deg", servo.letter,
                hypot(Double(before.x), Double(before.y)),
                hypot(Double(vector.x), Double(vector.y))))
        mappingWatch.reset(servo)
    }

    private func sendFollowMove(_ servo: StageAxis, _ angle: Int) {
        guard sendMove(servo, angle) else { return }
        movedSinceLastPress = true
        movedForStall = true
        inFlight = true
        moveSentAt = Date()
        lastServo = servo
        lastMove = "GOTO \(servo.letter) \(angle)"
        phase = .following
    }

    private func follow() {
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            // The reply never came (or the move was to the angle it is already at).
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
        }
        if crossing != nil {
            crossStep()
            return
        }
        let monitor = engine.setupInfo.monitor
        if stallWatch.update(
            now: Date(), holds: engine.guideInfo.holdsForPicture, moved: movedForStall,
            focusIndex: monitor.focusIndex, baseline: monitor.focusBaseline)
        {
            engine.requestFocusPause()
            lastMove = "Focus pause (stall)"
        }
        movedForStall = false
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
        if hypot(Double(target.x), Double(target.y)) > 0 { lastSteer = target }
        var planner = makePlanner(mapping)
        planner.deadbandFields = 0.15
        switch planner.next(angles: (angleX, angleY), target: target) {
        case .idle: break
        case .atLimit(let servo):
            phase = .atLimit(servo)
            // Only the column's own servo ends a column: a pinned cross-axis correction
            // must not press Stage limit.
            var heading: CGPoint?
            if let hx = engine.guideInfo.headingDx, let hy = engine.guideInfo.headingDy {
                heading = unstraightened(CGPoint(x: hx, y: hy))
            }
            let leg = heading.flatMap { StageLegServo.choose(heading: $0, mapping: mapping) }
            var crossStuck = false
            if let leg, leg != servo {
                if case .move(let legServo, let angle) = planner.move(
                    servo: leg, angles: (angleX, angleY), target: target)
                {
                    crossStuckSince = nil
                    sendFollowMove(legServo, angle)
                    break
                }
                let since = crossStuckSince ?? Date()
                crossStuckSince = since
                crossStuck = Date().timeIntervalSince(since) >= 5
            } else {
                crossStuckSince = nil
                crossStuck = true
            }
            if autoStageLimit,
                limitPress.update(
                    now: Date(), atLimit: crossStuck, lastSettledAt: lastSettledAt,
                    movedSinceLastPress: movedSinceLastPress)
            {
                engine.stageLimit(cause: .auto)
                if leg != nil, leg != servo {
                    engine.logEvent("stage_limit_auto", detail: "stage_limit_auto_cross")
                }
                autoStageLimitCount += 1
                movedSinceLastPress = false
                lastMove = "Stage limit (auto)"
            }
        case .move(let servo, let angle):
            crossStuckSince = nil
            sendFollowMove(servo, angle)
        }
    }
}

extension CGAffineTransform {
    fileprivate var withoutTranslation: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
    }
}
