import AudioToolbox
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
        /// At the stage step without a focus found in setup: waits for the person (or for focus).
        case waitingForFocus
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
        /// The guided scan waits at the stage step for the path: preset moves need no
        /// calibration, Follow the guide does.
        case choosingPath
        /// The board is being put in MANUAL (a manual session, or before preset moves).
        case preparingManual
        /// The person steers the stage with the arrows (lab only). Taken over from a path, the
        /// position before is saved.
        case byHand
        /// Moving the servos back to the saved angles.
        case returningFromHand(x: Int, y: Int)
        /// Back in place: waiting for the picture to be sharp before the path goes on.
        case checkingFocus
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
    /// The angles the servos may reach, as the board reports them (0...180 until it does).
    private(set) var limits = StageLimits()
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
    /// The path ran at least once since the last calibration.
    private var pathStarted = false
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
    /// The person said the picture is sharp (setup's own focus step was skipped).
    private var focusAccepted = false
    private var edgeAnswer = StageEdgeAnswer()
    private var zigzag: StageZigzag?
    /// How far the preset path has come; nil before it starts and while following the guide.
    private(set) var presetProgress: StageZigzagProgress?
    private var presetEvent: StageZigzagEvent?
    private var presetAwaitingSettle = false
    private var presetFinished = false
    private var dwellUntil: Date?
    private var countingColumn: Int?
    private var edgeWatch = StagePresetEdgeWatch()
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
    // Hand control (lab only): the person steers the stage while the path is paused.
    private struct HandControl {
        var saved: (x: Int, y: Int)
        var tracker: CGPoint
        /// Each servo's last real direction before the takeover: +1, -1 or 0.
        var direction: (x: Int, y: Int)
        var moved = (x: false, y: false)
    }
    private var handState: HandControl?
    private var handBegin = false
    /// The page's Auto | Manual change-over (see `StageManualSwitch`), and what to tell the person
    /// when the board did not answer.
    private(set) var manualSwitch = StageManualSwitch()
    private(set) var manualSwitchProblem: String?
    private var lastStopAt = Date.distantPast
    private var handRestartNotice = false
    private var hand = StageHandControl()
    private var handReturn: StageHandReturn?
    private var handLimitLogged: StageArrow?
    private var checkingSince = Date.distantPast
    /// The last real direction of each servo, from the angles the board reports.
    private var servoDirection = (x: 0, y: 0)
    /// Fine steps (the objective's smallest) instead of the chosen chunk.
    var handFine = false
    /// The limit or warning the pad shows.
    private(set) var handNote = ""
    /// Manual: steer with the arrows, no calibration. Autonomous: the stage moves by itself.
    /// Set before `activate`.
    var controlMode = StageControlMode.autonomous
    /// The arrows' flips (the Stage control lab's own, set by the pad).
    var handFlipX = false
    var handFlipY = false

    enum ManualProblem { case oldPath, noAnswer }
    /// Why a manual session could not start; nil otherwise.
    private(set) var manualProblem: ManualProblem?
    private var manualStarted = false
    private var manualPreparing = false
    private var manualStageSkipped = false
    /// Why the last calibration failed: the picture could not be tracked (too little sample), or
    /// the board did not answer. Nil when it has not failed.
    enum CalibrationFailureKind { case tracking, board }
    private(set) var lastCalibrationFailure: CalibrationFailureKind?
    /// Counts the failures, so a screen can tell a new one from the one it has shown.
    private(set) var calibrationFailureCount = 0
    /// The board was put in MANUAL and IDLE for preset moves (nothing moved).
    private var presetPrepared = false
    /// The guided scan's path was chosen (until then the driver waits in `.choosingPath`).
    private var pathChosen = false
    /// The stage step was reopened and is not yet seen as `.stage`: nothing calibrates before.
    private var awaitingReopen = false
    private var presetStageSkipped = false
    /// Y has moved 20 degrees or more since manual began or the last reminder was dismissed:
    /// "Check focus". Angles only.
    private(set) var handFocusReminder = false
    private var focusReminderBaseY = 90
    /// After "Switch to autonomous": the person says the picture is sharp before it calibrates.
    private var needsSharpTap = false
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
        limits = StageLimits()
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
        cancelSwitchToManual()
        engine.stageMoveSettled()
        clearHandState()
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
        lastStopAt = Date()
        inFlight = false
        releaseHandArrow()
        engine.setExternalCounting(active: false, column: 0)
        phase = .paused
    }

    func resume() {
        cancelSwitchToManual()
        manualSwitchProblem = nil
        userPaused = false
        guard phase == .paused else { return }
        sessionEnded = false
        if controlMode == .manual {
            continueManually()
            return
        }
        guard canRunPath else {
            phase = .waitingForStageStep
            return
        }
        if handState != nil {
            goBackAndResume()  // the way back first; the path carries on after it
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
        if controlMode == .manual {
            // No walk back: the person steers from wherever the board is.
            guard let saved = savedAngles else { return }
            savedAngles = nil
            if StageRestart.detected(saved: saved, reported: reported) {
                restartNotice =
                    "The stage restarted (check its power). It is at X \(reported.x)°, Y \(reported.y)°."
                engine.logEvent(
                    "stage_restart_detected",
                    detail: "saved \(saved.x),\(saved.y) reported \(reported.x),\(reported.y)")
            }
            return
        }
        guard let saved = savedAngles, let tracker = savedTrackerPosition else { return }
        savedAngles = nil
        savedTrackerPosition = nil
        guard StageRestart.detected(saved: saved, reported: reported) else { return }  // a plain drop
        if let handState {
            // The way back is the hand return's: it goes to where the person took over.
            handRestartNotice = true
            restartNotice =
                "The stage restarted (check its power). Go back and resume returns it to "
                + "\(handState.saved.x),\(handState.saved.y)."
            engine.logEvent(
                "stage_restart_detected",
                detail: "saved \(saved.x),\(saved.y) reported \(reported.x),\(reported.y)")
            return
        }
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
            engine.stageMoveSettled()
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
        guard sendGoTo(next.servo, next.angle) else { return }
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
        guard canRunPath else {
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
        clearHandState()
        pathMode = new
        zigzag = nil
        presetProgress = nil
        presetFinished = false
        presetEvent = nil
        presetAwaitingSettle = false
        dwellUntil = nil
        presetEdgePrompt = false
        countingColumn = nil
        engine.setExternalCounting(active: false, column: 0)
        engine.logEvent("path_mode_\(new.rawValue)")
        edgeWatch = StagePresetEdgeWatch()
        // Paused on preset moves, now Follow the guide, with no measurement: calibrate first.
        if controlMode == .autonomous, !requiresRunStart, new == .followGuide, mapping == nil,
            phase == .paused
        {
            beginFollowCalibration()
        }
    }

    /// Follow the guide without a measurement: the stage step is reopened if the identity axes
    /// stand, and calibration starts like a normal start.
    private func beginFollowCalibration() {
        presetPrepared = false
        userPaused = false
        if engine.setupInfo.step == .done {
            engine.reopenStage()
            awaitingReopen = true
        }
        phase = .waitingForStageStep
    }

    func endSession() {
        cancelSwitchToManual()
        guard !sessionEnded else { return }
        sessionEnded = true
        clearHandState()
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
        if controlMode != .manual { clearHandState() }  // manual: only the step size changes
        objective = new
        chunkDegrees = max(new.defaultChunk, new.minChunk)
        engine.logEvent("objective_\(new.title)")
        if controlMode == .manual {
            // The measurement was for the other lens: gone, but the manual session goes on.
            mapping = nil
            mappingSummary = ""
        } else if mapping != nil || presetPrepared {
            recalibrate()
        }
    }

    /// "It's sharp": calibrate although setup's focus step was skipped.
    func focusIsSharp() {
        guard phase == .waitingForFocus else { return }
        // After a switch to autonomous the setup step must really be the stage step again.
        if needsSharpTap, engine.setupInfo.step != .stage { return }
        needsSharpTap = false
        focusAccepted = true
        engine.recordCalibrateAccept()
        engine.logEvent("stage_focus_accepted")
        phase = .waitingForStageStep
    }

    /// The servos are measured: Follow the guide can start.
    var isCalibrated: Bool { mapping != nil }

    /// The path can run: preset moves need the board ready (never a calibration); Follow the
    /// guide needs the measurement.
    var canRunPath: Bool { pathMode == .presetPath ? presetPrepared : mapping != nil }

    /// The guided scan has not chosen its path yet.
    private var needsPathChoice: Bool { requiresRunStart && !pathChosen }

    /// After a failure, or to measure again at the stage step.
    func recalibrate() {
        guard controlMode != .manual else { return }  // manual never calibrates
        clearHandState()
        pathStarted = false
        presetPrepared = false
        pathChosen = false
        presetStageSkipped = false
        awaitingReopen = false
        zigzag = nil
        presetFinished = false
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
        engine.resumeFocusAnyway(emptyArea: true)
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
            switch reply {
            case .hello, .resumed:
                limits = StageLimits()  // a board is connected: its own limits follow
                // A path it was running would carry on by itself: no.
                if case .resumed = reply, controlMode == .manual { client.send(.stop) }
            default: break
            }
            if case .hello = reply {
                // A new connection can be a restart: the servos jumped, they did not turn.
            } else {
                if x != angleX { servoDirection.x = x > angleX ? 1 : -1 }
                if y != angleY { servoDirection.y = y > angleY ? 1 : -1 }
            }
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
            // The view is somewhere new: setup's focus step starts its guide afresh.
            engine.focusSpotChanged()
            engine.stageMoveSettled()
            // Every step starts from zero offset: a step can move the picture further than the
            // tracker trusts between two frames.
            engine.requestTrackerReanchor()
            if moveCheck != nil, moveCheck?.posAt == nil { moveCheck?.posAt = Date() }
            if isHandPhase { hand.settled() }
            if presetAwaitingSettle, zigzag != nil, !isHandPhase {
                presetAwaitingSettle = false
                presetEvent = .settled
            }
        case .ok(let text) where text.hasPrefix("STOP"):
            inFlight = false
            lastSettledAt = Date()
            // It may have stopped part way: frames from before now stay hidden.
            engine.stageMoveSettled()
        case .limits(let new):
            limits = new
        case .limitReached(let axis, let end):
            noteLimitReported(axis, end)
        case .error(let text):
            if inFlight { engine.stageMoveSettled() }
            inFlight = false
            lastErrorText = text
            if text.hasPrefix("LIMIT") { refused(text) }
            if isHandPhase { hand.settled() }
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

    /// Sends a GOTO; from the moment it is out the detector's boxes are hidden (drawing only).
    private func sendGoTo(_ servo: StageAxis, _ angle: Int) -> Bool {
        guard client.send(.goTo(servo, angle)) else { return false }
        engine.stageMoveStarted()
        return true
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
            if case .goTo = command { engine.stageMoveStarted() }
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
        lastServo = servo
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
        guard controlMode == .autonomous else { return }  // went back to manual before it began
        isCalibrating = true
        cancelSweep = false
        defer { isCalibrating = false }
        calibration = StageAutoCalibration()
        stuckWatch = StageStuckWatch()
        lastCalibrationFailure = nil
        presetPrepared = false  // the warm-up puts the board in AUTO
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
        guard homed else { return fail("The stage did not answer HOME", kind: .board) }
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
            return fail("The stage did not answer MODE MANUAL / HOME", kind: .board)
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
            if controlMode == .autonomous { phase = .calibrated(summary: mappingSummary) }
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
            limits.range(of: servo).contains(current + direction * calibrationStepDegrees)
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
        // Went back to manual: the manual phase stands, and so does any mapping.
        if controlMode == .manual { return }
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

    private func fail(_ message: String, kind: CalibrationFailureKind = .tracking) {
        collecting = nil
        if controlMode == .manual { return }  // a wound-down measurement says nothing now
        lastCalibrationFailure = kind
        calibrationFailureCount += 1
        phase = .failed(message)
    }

    // MARK: Following

    private func tick() {
        if client.status == .connected { hasConnected = true }
        updateAlert()
        guard client.status == .connected else {
            if phase != .disconnected, !isCalibrating {
                // The last position before the drop, to tell a restart from a plain drop.
                if controlMode == .manual {
                    if manualStarted, savedAngles == nil { savedAngles = (angleX, angleY) }
                    userPaused = true
                } else if canRunPath, savedAngles == nil, walkBack == nil {
                    savedAngles = (angleX, angleY)
                    savedTrackerPosition = engine.trackerPosition()
                }
                phase = .disconnected
                inFlight = false
                cancelSwitchToManual()
                engine.stageMoveSettled()
                releaseHandArrow()  // nothing moves again by itself
                userPaused = userPaused || canRunPath  // stay paused until Resume
            }
            return
        }
        reanchorIfStuckLost()
        let step = engine.setupInfo.step
        if controlMode == .manual {
            manualTick(step)
            return
        }
        if phase == .disconnected {
            phase = canRunPath && step == .done ? .paused : .waitingForStageStep
        }
        guard !isCalibrating else { return }
        if step != .done, step != .stage, mapping != nil || presetPrepared {
            recalibrate()  // setup went back: the old measurement is stale
            return
        }
        let atStage = step == .stage || step == .done
        if !atStage { focusAccepted = false }  // setup went back: focus is asked for again
        let hasFocus = engine.setupInfo.focusFound || focusAccepted
        if phase == .waitingForFocus, !needsSharpTap, hasFocus || !atStage {
            phase = .waitingForStageStep
        }
        if atStage, phase == .waitingForStageStep {
            if needsPathChoice {
                phase = .choosingPath  // the page asks which path before anything is measured
                return
            }
            if pathMode == .presetPath {
                // Never a calibration: the identity axes, and the board made ready.
                if step == .stage {
                    if !presetStageSkipped {
                        presetStageSkipped = true
                        engine.skipStage()
                    }
                    return
                }
                preparePreset()
                return
            }
            if awaitingReopen {
                guard step == .stage else { return }  // the old step is still published
                awaitingReopen = false
            }
            if mapping == nil {
                if !hasFocus || needsSharpTap {
                    phase = .waitingForFocus  // a blurry picture cannot be measured
                    return
                }
                phase = .calibrating(axis: .x, travel: 0)
                Task { await calibrate() }
                return
            }
        }
        guard step == .done else { return }
        guard canRunPath else { return }
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
        if phase == .choosingPath || phase == .preparingManual { return }
        if phase == .byHand {
            handTick()
            return
        }
        if case .returningFromHand = phase {
            returnStep()
            return
        }
        if phase == .checkingFocus {
            checkFocusStep()
            return
        }
        if userPaused || phase == .paused { return }
        if case .walkingBack = phase {
            walkBackStep()
            return
        }
        // The model does not count while the phone is too hot: the stage waits, so no part of the
        // slide goes by uncounted. A move on its way finishes.
        if engine.heatMode == .tooHot {
            stallWatch = StageStallWatch()
            return
        }
        if let zigzag {
            self.zigzag?.boostLeg = stuckWatch.extraDegrees(for: zigzag.plan.legServo)
            self.zigzag?.boostStep = stuckWatch.extraDegrees(for: zigzag.plan.stepServo)
        }
        pathStarted = true
        if pathMode == .presetPath { presetStep() } else { follow() }
    }

    /// The plain-words status, for the guided scan's screens.
    var status: AutoStageStatus {
        if isSwitchingToManual { return AutoStageStatus(title: "Switching to manual") }
        return AutoStageStatus.make(
            phase: phase, restartNotice: restartNotice, presetEdgePrompt: presetEdgePrompt,
            pathMode: pathMode, client: client.status, focusPaused: isFocusPaused,
            dwelling: isDwelling, hasConnected: hasConnected, tooHot: engine.heatMode == .tooHot)
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
        edgeWatch.newColumn()
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

    /// The preset path never uses a mapping: Y walks the columns, X steps across, in the arrows'
    /// directions; the stop spacing falls back to nominal fields per degree without tracking.
    private func startPreset() {
        // The stored flips, also when no pad was shown: the path starts where the arrows' Up and
        // Left lead.
        handFlipX = UserDefaults.standard.bool(forKey: "stageLab.flipX")
        handFlipY = UserDefaults.standard.bool(forKey: "stageLab.flipY")
        let plan = StageZigzagPlan(objective: objective, flipX: handFlipX, flipY: handFlipY)
        let zigzag = StageZigzag(
            plan: plan, chunkDegrees: chunkDegrees, dwellSeconds: dwellSeconds)
        self.zigzag = zigzag
        presetFinished = false
        edgeWatch = StagePresetEdgeWatch()
        let detail =
            "uncalibrated, nominal "
            + String(format: "%.3f", objective.nominalFieldsPerDegree) + " f/deg, "
            + zigzag.summary
        Task {
            // Another row, so the two events do not overwrite each other.
            try? await Task.sleep(for: .milliseconds(300))
            engine.logEvent("preset_path_start", detail: detail)
        }
    }

    /// Looks for the end of the sample along a leg, one stop at a time (see
    /// `StagePresetEdgeWatch`): what the view shows during a stop is noted here.
    private func watchPresetEdge() {
        guard dwellUntil != nil, (zigzag?.column ?? 0) > 0, !ignoreEdgeThisLeg, !presetEdgePrompt
        else { return }
        let viewClass = engine.guideInfo.viewClass
        let blank =
            viewClass == "blank"
            || (engine.guideInfo.holdsForPicture && trackingNow == .paused
                && viewClass != "blurry")
        edgeWatch.observe(isSample: viewClass == "sample" || viewClass == "thin", isBlank: blank)
    }

    private func presetStep() {
        if zigzag == nil {
            guard !presetFinished else { return }
            startPreset()
        }
        guard zigzag != nil else { return }
        zigzag?.dwellSeconds = dwellSeconds
        zigzag?.limits = limits
        zigzag?.chunkDegrees = max(chunkDegrees, 1)
        phase = .presetPath(column: zigzag?.column ?? 0, spot: zigzag?.spot ?? 0)
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
            engine.stageMoveSettled()
            if presetAwaitingSettle {
                presetAwaitingSettle = false
                presetEvent = .settled
            }
        }
        // A blurry view is the stall rule's (a focus pause), not an edge.
        let monitor = engine.setupInfo.monitor
        if stallWatch.update(
            now: Date(), holds: engine.guideInfo.holdsForPicture, moved: movedForStall,
            focusIndex: monitor.recentFocusIndex, baseline: monitor.focusBaseline)
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
            if (zigzag?.column ?? 0) > 0, !ignoreEdgeThisLeg, edgeWatch.endStop() {
                // The third blank stop in a row after sample: the column ends here.
                if restoreAsksEdges {
                    presetEdgePrompt = true  // the dwell stays over; Keep going carries on
                } else {
                    applyPresetEdge()
                }
                return
            }
            dwellUntil = nil
            presetEvent = .dwellDone
        }
        guard !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3 else { return }
        for _ in 0..<6 {
            defer {
                if let now = zigzag?.progress, now != presetProgress { presetProgress = now }
            }
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
                // Preset moves say nothing about a mapping: no move check.
                if sendMove(servo, angle, checked: false) {
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
                edgeWatch.beginStop()
                let detail = "column \(zigzag?.column ?? 0) at \(angleX),\(angleY)"
                Task {
                    // Another row than preset_path_column, so they do not overwrite each other.
                    try? await Task.sleep(for: .milliseconds(300))
                    engine.logEvent("preset_path_stop", detail: detail)
                }
                return
            case .columnStarted(let column):
                ignoreEdgeThisLeg = false
                edgeWatch.newColumn()
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
                presetProgress = zigzag?.progress
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
    private func sendMove(_ servo: StageAxis, _ angle: Int, checked: Bool = true) -> Bool {
        evaluateMoveCheck(force: true)
        guard sendGoTo(servo, angle) else { return false }
        moveCheck = nil
        if checked, trackingNow == .tracking, let seen = lastTracked,
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
        planner.limits = limits
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

    /// With edge questions off there is nobody to answer. The guide still asks two of them ("Edge
    /// should be here" and a line passed again and again), so the stage says yes itself.
    private func answerEdgeItself() {
        guard !asksEdgeQuestions,
            let id = edgeAnswer.update(questionID: engine.overlayState.questionID, now: Date())
        else { return }
        engine.answerEdge(.yes, questionID: id)
        engine.logEvent("edge_auto_yes", detail: "question=\(id)")
    }

    private func follow() {
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            // The reply never came (or the move was to the angle it is already at).
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
            engine.stageMoveSettled()
        }
        if crossing != nil {
            crossStep()
            return
        }
        let monitor = engine.setupInfo.monitor
        if stallWatch.update(
            now: Date(), holds: engine.guideInfo.holdsForPicture, moved: movedForStall,
            focusIndex: monitor.recentFocusIndex, baseline: monitor.focusBaseline)
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
            answerEdgeItself()
            return
        }
        edgeAnswer.questionGone()
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

// MARK: - Hand control (lab only; the guided scan never offers it)

extension AutoStageDriver {
    fileprivate var isHandPhase: Bool {
        switch phase {
        case .byHand, .returningFromHand, .checkingFocus: true
        default: false
        }
    }

    /// Where the servos are, as the board last said.
    var stageAngles: (x: Int, y: Int) { (angleX, angleY) }
    /// The position saved when the person took over; nil when there is none.
    var handSaved: (x: Int, y: Int)? { handState?.saved }

    /// Which way each arrow turns its servo: the board's angles and the flips, nothing else.
    var handDirections: StageArrowDirections {
        StageArrowDirections(flipX: handFlipX, flipY: handFlipY)
    }

    /// The flips may change while no arrow is active and no move is in flight.
    var canChangeFlips: Bool { hand.active == nil && !inFlight }
    /// Fine is offered only when it is smaller than the chosen chunk.
    var canFineStep: Bool { objective.minChunk < chunkDegrees }
    var handStepDegrees: Int { handFine && canFineStep ? objective.minChunk : chunkDegrees }

    /// Paused in a run that has started: the person may take over.
    var canMoveByHand: Bool {
        controlMode == .autonomous && phase == .paused && client.status == .connected
            && engine.setupInfo.step == .done && canRunPath && pathStarted && !presetFinished
            && !sessionEnded && walkBack == nil
            && engine.runSummary == nil && !isCalibrating
    }

    /// The saved position exists and the stage is connected: it can go back to it.
    var canGoBack: Bool {
        handState != nil && canRunPath && client.status == .connected && !isCalibrating
            && (phase == .byHand || phase == .paused)
    }

    func handEnabled(_ arrow: StageArrow) -> Bool {
        hand.enabled(
            arrow, directions: handDirections, angles: (angleX, angleY), step: handStepDegrees,
            limits: limits)
    }

    /// "Move by hand": the board's own X and Y, taken from a STATUS answer in IDLE, are the
    /// position to come back to. A position saved earlier stays the saved one.
    func beginHandControl() {
        guard canMoveByHand, !handBegin, !isSwitchingToManual else { return }
        handBegin = true
        Task {
            defer { handBegin = false }
            var reported: (x: Int, y: Int)?
            let answered = await request(.status, timeout: 3) { reply in
                guard case .status(_, let state, let x, let y, _) = reply else { return nil }
                guard state == .idle else { return false }
                reported = (x, y)
                return true
            }
            guard answered, let reported, canMoveByHand else {
                lastMove = "The stage did not answer"
                return
            }
            enterHandControl(at: reported)
        }
    }

    /// Hand control starts: the board is idle at `reported`. A position saved earlier stays the
    /// saved one.
    private func enterHandControl(at reported: (x: Int, y: Int)) {
        if handState == nil {
            handState = HandControl(
                saved: reported, tracker: engine.trackerPosition(), direction: servoDirection)
        }
        let saved = StageManualSwitch.saved(existing: handState?.saved, reported: reported)
        engine.logEvent("hand_start", detail: "\(saved.x),\(saved.y)")
        dismissHandFocusReminder()
        engine.setHandHold(.on)
        stallWatch = StageStallWatch()
        hand.reset()
        handNote = ""
        handLimitLogged = nil
        phase = .byHand
    }

    // MARK: Auto | Manual

    /// A change-over is under way (the switch shows Manual, the status says so).
    var isSwitchingToManual: Bool { manualSwitch.state == .switching }

    /// The run may be switched to manual: see `StageManualSwitch.canSwitch`.
    var canSwitchToManual: Bool {
        StageManualSwitch.canSwitch(
            phase: phase, isAutonomous: controlMode == .autonomous,
            isConnected: client.status == .connected,
            pathRuns: engine.setupInfo.step == .done && canRunPath && pathStarted && !presetFinished,
            sessionEnded: sessionEnded, walkingBack: walkBack != nil,
            hasSummary: engine.runSummary != nil, isCalibrating: isCalibrating)
    }

    /// Pauses (unless paused), waits for the board to say IDLE, then starts hand control as
    /// `beginHandControl` does. Only STOP (the pause) and STATUS are sent; nothing moves. When the
    /// board does not answer or is not idle it stays paused, and `manualSwitchProblem` says so.
    func switchToManual() {
        guard canSwitchToManual, !handBegin, let token = manualSwitch.begin() else { return }
        manualSwitchProblem = nil
        if StageManualSwitch.needsPause(phase) { pause() }
        Task {
            var lastAsk: Date?
            while let delay = manualSwitch.nextAsk(
                sinceStop: Date().timeIntervalSince(lastStopAt),
                sinceLastAsk: lastAsk.map { Date().timeIntervalSince($0) })
            {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard manualSwitch.isCurrent(token) else { return }
                guard client.status == .connected else { return cancelSwitchToManual() }
                lastAsk = Date()
                var reading: StageManualSwitch.Reading?
                _ = await request(.status, timeout: 3) { reply in
                    guard case .status(_, let state, let x, let y, _) = reply else { return nil }
                    reading = .init(x: x, y: y, isIdle: state == .idle)
                    return true
                }
                guard manualSwitch.isCurrent(token) else { return }
                if let outcome = manualSwitch.record(reading) {
                    finishSwitch(outcome)
                    return
                }
            }
        }
    }

    private func finishSwitch(_ outcome: StageManualSwitch.Outcome) {
        switch outcome {
        case .entered(let x, let y) where canMoveByHand:
            enterHandControl(at: (x, y))
        default:
            lastMove = "The stage did not answer"
            manualSwitchProblem = StageManualSwitch.didNotAnswerText
        }
    }

    /// Ends a change-over without entering manual: a disconnect, the app in the background,
    /// End run, Stop and discard, the page closing, or Resume. Does nothing when none is under way.
    func cancelSwitchToManual() {
        manualSwitch.cancel()
    }

    func handPress(_ arrow: StageArrow) {
        guard phase == .byHand, hand.press(arrow) else { return }
        if handNote.hasPrefix("Stage limit") { handNote = "" }
        handAdvance(atOnce: true)
    }

    /// The finger is up: the step under way finishes, and nothing else is sent.
    func handRelease(_ arrow: StageArrow) {
        guard hand.active == arrow else { return }  // another finger's arrow says nothing
        handReleaseAll()
    }

    /// Every arrow up: the pad going away, or the scene being left.
    func handReleaseAll() {
        hand.release()
        handLimitLogged = nil
    }

    /// Stops the stage and lets go of the arrow; stays in hand control.
    func handStop() {
        guard phase == .byHand else { return }
        client.send(.stop)
        inFlight = false
        lastSettledAt = Date()
        releaseHandArrow()
    }

    fileprivate func releaseHandArrow() {
        hand.reset()
    }

    /// "OK" on the reminder: Y counts from where it is now.
    func dismissHandFocusReminder() {
        handFocusReminder = false
        focusReminderBaseY = angleY
    }

    private func handTick() {
        if abs(angleY - focusReminderBaseY) >= 20 { handFocusReminder = true }
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
            engine.stageMoveSettled()
            releaseHandArrow()
            return
        }
        handAdvance(atOnce: false)
    }

    /// Sends the active arrow's next move, one at a time: at once on a press, after the POS and
    /// the rest while it stays pressed.
    private func handAdvance(atOnce: Bool) {
        guard hand.wantsMove, let arrow = hand.active else { return }
        let directions = handDirections
        let servo = arrow.axis
        let current = servo == .x ? angleX : angleY
        guard
            let target = directions.nextAngle(
                arrow, from: current, step: handStepDegrees, limits: limits)
        else {
            hand.blocked()
            reportHandLimit(arrow, at: current)
            return
        }
        guard !inFlight, atOnce || Date().timeIntervalSince(lastSettledAt) >= 0.3 else { return }
        moveCheck = nil  // a hand move says nothing about the mapping or the gear
        guard sendGoTo(servo, target) else { return }
        hand.sent()
        inFlight = true
        moveSentAt = Date()
        lastServo = servo
        if servo == .x { handState?.moved.x = true } else { handState?.moved.y = true }
        lastMove = "GOTO \(servo.letter) \(target) (by hand)"
        engine.logEvent(
            "hand_move", detail: "\(servo.letter) \(String(format: "%+d", target - current)) -> \(target)")
    }

    private func reportHandLimit(_ arrow: StageArrow, at angle: Int) {
        handNote = "Stage limit: \(arrow.axis.letter) can't go further \(arrow.word)"
        guard handLimitLogged != arrow else { return }
        handLimitLogged = arrow
        AudioServicesPlaySystemSound(1104)
        engine.logEvent("hand_limit", detail: "\(arrow.axis.letter) \(arrow.word) \(angle)")
    }

    /// The board refused a move ("ERR LIMIT a-b"): its range is learned, and whatever waited for
    /// that move goes on.
    fileprivate func refused(_ text: String) {
        limits.merge(refusal: text, axis: lastServo)
        if pathMode == .presetPath, zigzag != nil, presetAwaitingSettle, !isHandPhase {
            presetAwaitingSettle = false
            presetEvent = .settled  // the sweep goes on from where the servo is
        }
        switch phase {
        case .returningFromHand:
            userPaused = true
            phase = .paused
            lastMove = "Could not go back: stage limit"
        case .byHand:
            if let arrow = hand.active {
                hand.blocked()
                reportHandLimit(arrow, at: arrow.axis == .x ? angleX : angleY)
            }
        default: break
        }
    }

    fileprivate func noteLimitReported(_ axis: StageAxis, _ end: StageLimitEnd) {
        guard !isCalibrating, !sessionEnded else { return }
        let word: String
        if controlMode == .manual {
            guard phase == .byHand || phase == .paused || phase == .preparingManual else { return }
            word = "manual"
        } else {
            guard canRunPath else { return }
            switch phase {
            case .following, .waitingForEdgeAnswer, .atLimit: word = "following"
            case .presetPath: word = "preset"
            case .paused: word = "paused"
            case .byHand: word = "by_hand"
            case .returningFromHand: word = "returning"
            case .checkingFocus: word = "checking_focus"
            case .walkingBack: word = "walking_back"
            case .crossingEmpty, .emptyCapReached: word = "crossing"
            default: return  // warming up, calibrating, not connected: nothing to say
            }
        }
        let range = limits.range(of: axis)
        let angle = end == .min ? range.lowerBound : range.upperBound
        engine.logEvent(
            "stage_limit_reported",
            detail: "\(axis.letter) \(end == .min ? "MIN" : "MAX") \(angle) \(word)")
    }

    // MARK: Going back

    /// Back to the saved position (Y first, then X, past it first when it must be approached
    /// from the side the servo came from), then a check of the focus, then the path goes on.
    func goBackAndResume() {
        guard let saved = handState, canGoBack else { return }
        releaseHandArrow()
        handNote = ""
        handReturn = StageHandReturn(
            saved: saved.saved, chunk: max(chunkDegrees, 1), limits: limits, moved: saved.moved,
            direction: saved.direction)
        engine.setHandHold(.on)
        logSpaced([
            ("hand_end", "\(angleX),\(angleY)"),
            ("hand_return", "\(saved.saved.x),\(saved.saved.y)"),
        ])
        userPaused = false
        phase = .returningFromHand(x: saved.saved.x, y: saved.saved.y)
    }

    private func returnStep() {
        guard let saved = handState else { return resumeWhereItStopped() }
        if inFlight, Date().timeIntervalSince(moveSentAt) > 5 {
            inFlight = false
            lastSettledAt = Date()
            client.send(.status)
            lastMove = "No reply, resynced"
            engine.stageMoveSettled()
        }
        guard !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3 else { return }
        if let next = handReturn?.nextStep(angles: (angleX, angleY)) {
            moveCheck = nil  // these moves say nothing about the mapping
            guard sendGoTo(next.servo, next.angle) else { return }
            inFlight = true
            moveSentAt = Date()
            lastServo = next.servo
            lastMove = "GOTO \(next.servo.letter) \(next.angle) (back)"
            return
        }
        // The hardware angles are the truth: the map is put back to match them, always.
        engine.restoreTrackerPosition(to: saved.tracker)
        engine.logEvent("hand_returned", detail: "\(saved.saved.x),\(saved.saved.y)")
        engine.setHandHold(.checkingFocus)
        stallWatch = StageStallWatch()
        handReturn = nil
        checkingSince = Date()
        phase = .checkingFocus
    }

    private func checkFocusStep() {
        guard Date().timeIntervalSince(checkingSince) >= 3,
            engine.setupInfo.monitor.state == .ok
        else { return }
        clearHandState()  // the hold ends, and so does the saved position
        resumeWhereItStopped()
    }

    /// Ends hand control for good: the hold, the saved position and the notice.
    fileprivate func clearHandState() {
        let wasHeld = handState != nil || isHandPhase || manualStarted
        manualStarted = false
        handState = nil
        handReturn = nil
        releaseHandArrow()
        handNote = ""
        handLimitLogged = nil
        if handRestartNotice {
            restartNotice = nil
            handRestartNotice = false
        }
        guard wasHeld else { return }
        engine.setHandHold(.off)
        stallWatch = StageStallWatch()
        if isHandPhase { phase = .paused }
    }
}

// MARK: - Manual session (lab only): the arrows, no calibration

extension AutoStageDriver {
    /// What a manual session does each tick. It never looks at a mapping, the tracker or the
    /// picture: the board's angles and limits are all it uses.
    fileprivate func manualTick(_ step: LabSetupStep) {
        // A measurement winding down must not be overwritten (or overwrite) a manual phase.
        guard !isCalibrating else { return }
        if phase == .disconnected {
            phase = manualStarted && step == .done ? .paused : .waitingForStageStep
        }
        guard step == .stage || step == .done else {
            // Setup went back (Redo setup): the arrow lets go, the hold ends, setup runs again.
            manualStageSkipped = false
            mapping = nil  // the old measurement is stale once setup goes back
            mappingSummary = ""
            presetPrepared = false
            pathChosen = false
            if phase != .waitingForStageStep || manualStarted {
                releaseHandArrow()
                engine.setHandHold(.off)
                manualStarted = false
                manualProblem = nil
                phase = .waitingForStageStep
            }
            return
        }
        if step == .stage {
            if !manualStageSkipped, mapping == nil {
                manualStageSkipped = true
                engine.skipStage()  // no stage axes to measure: the identity
            }
            return
        }
        switch phase {
        case .waitingForStageStep: prepareManual()
        case .byHand: handTick()
        default: break
        }
    }

    /// From Paused (Pause, a reconnect, or a start that did not work): the arrows again.
    func continueManually() {
        guard controlMode == .manual, client.status == .connected,
            engine.setupInfo.step == .done, phase == .paused
        else { return }
        restartNotice = nil
        prepareManual()
    }

    /// The board still holds an old path: HOME clears it (and moves), then it starts again.
    func goToCentre() {
        guard manualProblem == .oldPath, phase == .paused, client.status == .connected
        else { return }
        if controlMode == .manual {
            prepareManual(centreFirst: true)
        } else {
            preparePreset(centreFirst: true)
        }
    }

    private enum BoardPreparation { case ready, oldPath, noAnswer, interrupted }

    /// STOP, then STATUS; the board must be MANUAL and IDLE. An AUTO board with nothing queued
    /// is put in MANUAL. Nothing moves on the way in, other than HOME on "Go to centre". Shared
    /// by a manual session and by preset moves (both phases are `.preparingManual`).
    private func prepareBoard(centreFirst: Bool) async -> BoardPreparation {
        if centreFirst {
            let homed = await request(.home, timeout: 20) {
                if case .done = $0 { return true }
                if case .error = $0 { return false }
                return nil
            }
            guard homed else { return .noAnswer }
        }
        client.send(.stop)
        var report: (mode: StageMode, state: StageRunState, queued: Int)?
        func askStatus() async -> Bool {
            await request(.status, timeout: 3) { reply in
                guard case .status(let mode, let state, _, _, let queued) = reply else {
                    return nil
                }
                report = (mode, state, queued)
                return true
            }
        }
        guard await askStatus(), var seen = report else { return .noAnswer }
        if seen.mode == .auto {
            guard seen.state == .idle, seen.queued == 0 else { return .oldPath }
            let manual = await request(.mode(.manual), timeout: 3) {
                if case .ok(let text) = $0, text.hasPrefix("MODE") { return true }
                if case .error = $0 { return false }  // ERR BUSY
                return nil
            }
            guard manual else { return .oldPath }
            guard await askStatus(), let again = report else { return .noAnswer }
            seen = again
        }
        guard seen.mode == .manual, seen.state == .idle else { return .noAnswer }
        guard phase == .preparingManual, client.status == .connected else { return .interrupted }
        return .ready
    }

    private func prepareManual(centreFirst: Bool = false) {
        guard !manualPreparing else { return }
        manualPreparing = true
        manualProblem = nil
        userPaused = false
        phase = .preparingManual
        Task {
            defer { manualPreparing = false }
            switch await prepareBoard(centreFirst: centreFirst) {
            case .oldPath: return manualFailed(.oldPath)
            case .noAnswer: return manualFailed(.noAnswer)
            case .interrupted: return
            case .ready: break
            }
            engine.setHandHold(.on)
            stallWatch = StageStallWatch()
            hand.reset()
            handNote = ""
            handLimitLogged = nil
            manualStarted = true
            inFlight = false
            dismissHandFocusReminder()
            engine.logEvent("control_manual_start", detail: "\(angleX),\(angleY)")
            phase = .byHand
        }
    }

    /// Preset moves: the board made ready as for a manual session, and nothing else. No HOME, no
    /// warm-up, no calibration, no move: the path starts with the run.
    private func preparePreset(centreFirst: Bool = false) {
        guard !manualPreparing else { return }
        presetPrepared = false
        manualPreparing = true
        manualProblem = nil
        userPaused = false
        phase = .preparingManual
        Task {
            defer { manualPreparing = false }
            switch await prepareBoard(centreFirst: centreFirst) {
            case .oldPath: return manualFailed(.oldPath)
            case .noAnswer: return manualFailed(.noAnswer)
            case .interrupted: return
            case .ready: break
            }
            presetPrepared = true
            inFlight = false
            enterPathPhase()
        }
    }

    /// Ready to run: waits for Start scan in the guided scan, otherwise the path begins.
    private func enterPathPhase() {
        if requiresRunStart, !runBegun {
            phase = .readyToStart
        } else {
            phase = pathMode == .presetPath ? .presetPath(column: 0, spot: 0) : .following
        }
    }

    private func manualFailed(_ problem: ManualProblem) {
        guard phase == .preparingManual else { return }  // paused or dropped meanwhile
        manualProblem = problem
        phase = .paused
    }

    /// Enabled when connected, no arrow is held and no move is in flight.
    var canSwitchToAutonomous: Bool {
        controlMode == .manual && client.status == .connected && hand.active == nil && !inFlight
            && (phase == .byHand || phase == .paused)
    }

    /// Before the run: back from autonomous to manual (a measurement in progress is cancelled).
    var canBackToManual: Bool {
        guard controlMode == .autonomous, !runBegun, !pathStarted else { return false }
        switch phase {
        case .choosingPath, .readyToStart, .calibrated, .waitingForFocus, .failed, .warmingUp,
            .calibrating, .paused:
            return true
        default: return false
        }
    }

    func backToManual() {
        guard canBackToManual else { return }
        cancelSweep = true
        finishWaiter(false)
        if client.status == .connected { client.send(.stop) }
        inFlight = false
        needsSharpTap = false
        sessionEnded = false  // and its END is sent again when it ends
        controlMode = .manual
        manualStarted = false
        manualStageSkipped = false  // a reopened stage step is skipped again
        manualProblem = nil
        engine.logEvent("control_back_manual")
        phase = .waitingForStageStep  // manualTick takes it from here, once a measurement is over
    }

    /// "Try again" after a failed calibration: measures again for Follow the guide (the path
    /// stays chosen).
    func retryCalibration() {
        guard case .failed = phase else { return }
        recalibrate()
        pathChosen = true
    }

    /// The path can still be chosen or changed: before the run, outside a measurement.
    var canChoosePath: Bool {
        guard controlMode == .autonomous, !runBegun, !pathStarted else { return false }
        switch phase {
        case .choosingPath, .readyToStart, .calibrated, .failed, .waitingForFocus, .paused:
            return true
        default: return false
        }
    }

    /// The guided scan's path. Preset moves: the board is made ready, nothing is measured.
    /// Follow the guide: measured once per test (an existing measurement stands; without one the
    /// stage step is reopened if the identity axes stand, and it calibrates like a normal start).
    func choosePath(_ path: StagePathMode) {
        guard canChoosePath else { return }
        pathChosen = true
        userPaused = false
        manualProblem = nil
        restartNotice = nil
        if path != pathMode { setPathMode(path) }
        switch path {
        case .presetPath:
            presetPrepared = false
            phase = .waitingForStageStep  // tick skips the stage step and prepares the board
        case .followGuide:
            if mapping != nil {
                if requiresRunStart, !runBegun {
                    phase = .readyToStart
                } else {
                    // As after a hand return: the focus is checked, then the path goes on.
                    engine.setHandHold(.checkingFocus)
                    checkingSince = Date()
                    phase = .checkingFocus
                }
            } else {
                presetStageSkipped = false
                if engine.setupInfo.step == .done {
                    engine.reopenStage()  // the identity axes were taken: measure for real
                    awaitingReopen = true
                }
                phase = .waitingForStageStep
            }
        }
    }

    /// Switch to autonomous. Nothing moves and nothing is measured here: the path is chosen next
    /// (`path` nil: the page asks; the lab passes one). Follow the guide without a measurement
    /// asks the person to say the picture is sharp first, as they may have moved out of focus.
    func switchToAutonomous(_ path: StagePathMode?) {
        guard canSwitchToAutonomous else { return }
        releaseHandArrow()
        stallWatch = StageStallWatch()
        userPaused = false  // a Pause in manual does not hold the run back
        controlMode = .autonomous
        manualStarted = false
        manualProblem = nil
        restartNotice = nil
        savedAngles = nil
        handNote = ""
        engine.setHandHold(.off)
        presetPrepared = false
        pathChosen = false
        needsSharpTap = mapping == nil
        engine.logEvent(
            "control_switch_autonomous",
            detail: mapping != nil ? "calibrated" : (path?.rawValue ?? ""))
        engine.restartGuide()
        phase = .choosingPath
        if let path { choosePath(path) }
    }
}
