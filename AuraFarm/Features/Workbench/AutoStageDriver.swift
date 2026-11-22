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
            case warmingUp(String)
            case calibrating(axis: StageAxis, travel: Double)
            case calibrated(summary: String)
            case following
            case waitingForEdgeAnswer
            case atLimit(StageAxis)
            case crossingEmpty(fields: Double)
            case emptyCapReached(fields: Double)
            case presetPath(column: Int, spot: Int)
            case paused
            case failed(String)
        }

        /// What the focus-pause banner asks about an empty-looking patch.
        enum EmptyPrompt: Equatable {
            /// Waits for the person.
            case blurry
            /// Counts down, then acts as "In focus – empty area".
            case sharp(secondsLeft: Int)

            var title: String {
                switch self {
                case .blurry: "Looks out of focus: refocus"
                case .sharp: "Looks in focus but empty"
                }
            }
        }

        let client = StageBLEClient()
        private(set) var emptyPrompt: EmptyPrompt?
        private(set) var phase = Phase.disconnected
        private(set) var lastMove = ""
        private(set) var mappingSummary = ""
        var chunkDegrees = 3
        /// The objective in use; set before `activate`. The step size starts at its default.
        var objective = StageObjective.x40
        /// A path run before calibration, so the linkage is past its slack and stick-slip.
        var warmUp: StagePresetPath? = .centreCross
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
        private var limitPress = StageLimitAutoPress()
        private var stallWatch = StageStallWatch()
        private var mappingWatch = StageMappingWatch()
        /// The move being checked against the mapping: where the picture was when it was sent.
        private var moveCheck: (servo: StageAxis, from: Int, before: CGPoint, lost: Bool, posAt: Date?)?
        /// The latest tracked guide position (raw), and when it was seen.
        private var lastTracked: (position: CGPoint, at: Date)?
        // The preset zig-zag.
        private var zigzag: StageZigzag?
        private var presetEvent: StageZigzagEvent?
        private var presetAwaitingSettle = false
        private var presetFinished = false
        private var dwellUntil: Date?
        private var countingColumn: Int?
        /// A dwell was cut short by the empty-patch question.
        private var dwellInterrupted = false
        /// The preset path crossing an empty patch: where the leg servo started and how far it may go.
        private var presetEmptyWalk: (startAngle: Int, capDegrees: Int)?
        private var emptyDeadline: Date?
        private var emptyFiredAt = Date.distantPast
        private let emptyCountdownSeconds = 5.0
        /// Since when the leg servo could not move while a cross-axis servo is pinned.
        private var crossStuckSince: Date?
        /// The last direction the guide steered in (raw guide fields), for crossing blind.
        private var lastSteer: CGPoint?
        private var crossing: StageBlindCrossing?
        private var crossingLogged = false
        private var trackingNow = TrackingState.lost
        /// How far the current crossing may go before the person is asked, in fields.
        private(set) var blindCap = 2.0
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

        init(engine: SlideMovementLabModel) { self.engine = engine }

        // MARK: On / off

        func activate(restoringAsksEdges previous: Bool) {
            restoreAsksEdges = previous
            engine.setAsksEdges(true)
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
            clearEmptyState()
            if client.status == .connected { client.send(.stop) }
            engine.setAsksEdges(restoreAsksEdges)
            engine.onGuideSample = nil
            client.onReply = nil
            client.disconnect()
            finishWaiter(false)
        }

        // MARK: Buttons

        func pause() {
            if crossing != nil { finishCrossing("blind_cross_paused") }
            clearEmptyState()
            userPaused = true
            cancelSweep = true
            client.send(.stop)
            inFlight = false
            engine.setExternalCounting(active: false, column: 0)
            phase = .paused
        }

        func resume() {
            userPaused = false
            guard phase == .paused else { return }
            guard mapping != nil else {
                phase = .waitingForStageStep
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
            clearEmptyState()
            countingColumn = nil
            engine.setExternalCounting(active: false, column: 0)
            engine.logEvent("path_mode_\(new.rawValue)")
        }

        func endSession() {
            clearEmptyState()
            userPaused = true
            cancelSweep = true
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
            mapping = nil
            mappingSummary = ""
            phase = .waitingForStageStep
        }

        // MARK: Crossing an empty patch

        /// The focus-pause banner may offer "In focus – empty area".
        var canConfirmEmptyArea: Bool {
            guard mapping != nil else { return false }
            if pathMode == .followGuide { return phase == .following }
            if case .presetPath = phase { return true }
            return false
        }

        /// The person says the view is in focus: it is an empty patch.
        func confirmEmptyArea() {
            guard canConfirmEmptyArea else { return }
            confirmEmpty(auto: false)
        }

        /// "Refocus" on the countdown: the banner waits for the person.
        func refocusEmpty() {
            guard case .sharp = emptyPrompt else { return }
            emptyPrompt = .blurry
            emptyDeadline = nil
            engine.logEvent("empty_countdown_cancelled", detail: "refocus")
        }

        /// Follow guide crosses the patch blind; the preset path keeps walking its leg with no dwell.
        private func confirmEmpty(auto: Bool) {
            if pathMode == .followGuide {
                guard let lastSteer, hypot(Double(lastSteer.x), Double(lastSteer.y)) > 0 else {
                    lastMove = "No direction to cross in"
                    if auto {
                        emptyPrompt = .blurry
                        emptyDeadline = nil
                    }
                    return
                }
                crossing = StageBlindCrossing(direction: lastSteer, startAngles: (angleX, angleY))
                blindCap = crossing?.capFields ?? 2.0
                crossingLogged = false
                phase = .crossingEmpty(fields: 0)
            } else {
                beginPresetEmptyWalk()
            }
            engine.resumeFocusAnyway()
            engine.logEvent(auto ? "empty_auto_confirmed" : "empty_confirmed")
            emptyPrompt = nil
            emptyDeadline = nil
        }

        private func clearEmptyState() {
            emptyPrompt = nil
            emptyDeadline = nil
            dwellInterrupted = false
            presetEmptyWalk = nil
            zigzag?.walksBlind = false
        }

        private func logLater(_ name: String, detail: String = "", after seconds: Double = 0.3) {
            Task {
                // Another row than the event logged now, so they do not overwrite each other.
                try? await Task.sleep(for: .seconds(seconds))
                engine.logEvent(name, detail: detail)
            }
        }

        /// What this frame says about detail: none (the guide holds, or blank / blurry) or some
        /// (sample / thin while tracking).
        private var frameDetail: (noDetail: Bool, hasDetail: Bool) {
            let info = engine.guideInfo
            let shown = info.viewClass == "sample" || info.viewClass == "thin"
            let hasDetail = trackingNow == .tracking && shown && !info.holdsForPicture
            let noDetail =
                info.holdsForPicture || info.viewClass == "blank" || info.viewClass == "blurry"
            return (noDetail && !hasDetail, hasDetail)
        }

        /// Watches for a patch with no detail, asks about it through the focus pause, and runs the
        /// countdown. Returns true while moves must wait.
        private func watchEmpty() -> Bool {
            let now = Date()
            let monitor = engine.setupInfo.monitor
            let frame = frameDetail
            if stallWatch.update(now: now, noDetail: frame.noDetail, hasDetail: frame.hasDetail),
                presetEmptyWalk == nil
            {
                fireEmptyWatch(monitor)
            }
            if let prompt = emptyPrompt {
                if monitor.state == .ok, now.timeIntervalSince(emptyFiredAt) > 1 {
                    // Detail came back and the focus pause ended: carry on where it stopped.
                    if case .sharp = prompt {
                        engine.logEvent("empty_countdown_cancelled", detail: "detail_back")
                    }
                    emptyPrompt = nil
                    emptyDeadline = nil
                    if dwellInterrupted {
                        dwellInterrupted = false
                        dwellUntil = now.addingTimeInterval(dwellSeconds)
                    }
                } else if case .sharp = prompt, let deadline = emptyDeadline {
                    if now >= deadline {
                        confirmEmpty(auto: true)
                    } else {
                        emptyPrompt = .sharp(secondsLeft: Int(deadline.timeIntervalSince(now).rounded(.up)))
                    }
                }
            }
            return emptyPrompt != nil || monitor.state != .ok
        }

        private func fireEmptyWatch(_ monitor: RunMonitorInfo) {
            if inFlight {
                client.send(.stop)
                inFlight = false
                lastSettledAt = Date()
            }
            if pathMode == .presetPath {
                if presetAwaitingSettle {  // the move that was stopped counts as done
                    presetAwaitingSettle = false
                    presetEvent = .settled
                }
                if dwellUntil != nil {
                    dwellUntil = nil
                    dwellInterrupted = true
                }
            }
            engine.requestFocusPause()
            emptyFiredAt = Date()
            let kind = stallWatch.kind(focusIndex: monitor.focusIndex, baseline: monitor.focusBaseline)
            let numbers = String(
                format: "index=%.3f baseline=%.3f", monitor.focusIndex ?? -1, monitor.focusBaseline ?? -1)
            lastMove = "Looks empty: stopped"
            if kind == .sharp {
                emptyPrompt = .sharp(secondsLeft: Int(emptyCountdownSeconds))
                emptyDeadline = Date().addingTimeInterval(emptyCountdownSeconds)
                logLater("empty_countdown_started", after: 0.6)
            } else {
                emptyPrompt = .blurry
            }
            logLater("empty_watch_fired", detail: "\(kind == .sharp ? "sharp" : "blurry") \(numbers)")
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
            var planner = StageMotionPlanner(mapping: mapping, chunkDegrees: chunkDegrees)
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
            if let preset = warmUp {
                await warmUpStage(preset)
                if sweepStopped { return stopSweep() }
            }
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
                while calibration.travel(of: servo) < calibration.minTravelFields
                    || calibration.movingAngles(of: servo) < 5,
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
                // Back to where it began, in the same steps, so the tracker follows the picture
                // there (one big jump loses it, and the next servo's samples start from a wrong
                // position).
                while current != start {
                    let back = current - direction * calibrationStepDegrees
                    current = direction > 0 ? max(back, start) : min(back, start)
                    guard await goTo(servo, current) else { break }
                }
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

        /// Runs a preset path in AUTO to take up the linkage's slack before calibrating. A timeout
        /// or an ERR is logged and calibration carries on.
        private func warmUpStage(_ preset: StagePresetPath) async {
            phase = .warmingUp(preset.title)
            engine.logEvent("warmup_start", detail: preset.title)
            func answered(_ reply: StageReply, ok: (String) -> Bool) -> Bool? {
                if case .ok(let text) = reply { return ok(text) ? true : nil }
                if case .error = reply { return false }
                return nil
            }
            var finished = false
            if await request(.mode(.auto), accept: { answered($0) { $0.hasPrefix("MODE") } }),
                !sweepStopped,
                await request(
                    .path(preset.points), accept: { answered($0) { $0.hasPrefix("PATH") } }),
                !sweepStopped
            {
                finished = await request(
                    .start, timeout: 90,
                    accept: {
                        if case .done = $0 { return true }
                        if case .error = $0 { return false }
                        return nil
                    })
            }
            if sweepStopped {
                client.send(.stop)
                return
            }
            if finished {
                engine.logEvent("warmup_done", detail: preset.title)
            } else {
                client.send(.stop)
                engine.logEvent("warmup_failed", detail: "\(preset.title): \(lastErrorText)")
            }
        }

        // MARK: Stopping a measurement

        private var sweepStopped: Bool { cancelSweep || client.status != .connected }

        /// Pause / End session / disconnect during the warm-up or calibration: measure again on Resume.
        private func stopSweep() {
            mapping = nil
            mappingSummary = ""
            if phase != .paused, phase != .disconnected { phase = .paused }
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
            if case .calibrated = phase {
                phase = pathMode == .presetPath ? .presetPath(column: 0, spot: 0) : .following
                if pathMode == .followGuide { engine.logEvent("stage_mapping", detail: mappingSummary) }
            }
            if userPaused || phase == .paused { return }
            if pathMode == .presetPath { presetStep() } else { follow() }
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
            if presetAwaitingSettle {  // the move that was stopped counts as done
                presetAwaitingSettle = false
                presetEvent = .settled
            }
            beginPresetEmptyWalk()  // another stretch of blind walking
        }

        /// Keeps walking the leg in steps with no dwell, as far as the blind crossing's cap.
        private func beginPresetEmptyWalk() {
            guard let zigzag, zigzag.column > 0 else { return }
            let start = zigzag.plan.legServo == .x ? angleX : angleY
            // The blind crossing's default cap (2 fields), in degrees of the leg servo.
            let cap = max(chunkDegrees, Int((2.0 / zigzag.legFieldsPerDegree).rounded(.up)))
            presetEmptyWalk = (start, cap)
            self.zigzag?.walksBlind = true
            if dwellInterrupted {
                dwellInterrupted = false
                presetEvent = .dwellDone
            }
            logLater("preset_empty_walk_start", detail: "cap \(cap)°")
        }

        private func endPresetEmptyWalk(_ reason: String) {
            guard presetEmptyWalk != nil else { return }
            presetEmptyWalk = nil
            zigzag?.walksBlind = false
            logLater("preset_empty_walk_end", detail: reason)
        }

        /// While walking blind: detail back returns to normal stepping; the cap reached is the
        /// edge. Returns true when it stopped the stage for the edge.
        private func checkPresetEmptyWalk() -> Bool {
            guard let walk = presetEmptyWalk, let zigzag else { return false }
            if frameDetail.hasDetail {
                endPresetEmptyWalk("detail_back")
                return false
            }
            let angle = zigzag.plan.legServo == .x ? angleX : angleY
            guard abs(angle - walk.startAngle) >= walk.capDegrees else { return false }
            endPresetEmptyWalk("edge")
            presetEdgeFound()
            return true
        }

        private func presetEdgeFound() {
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

        private func applyPresetEdge() {
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

        private func presetStep() {
            guard let mapping else { return }
            if zigzag == nil {
                guard !presetFinished else { return }
                startPreset(mapping)
            }
            guard zigzag != nil else { return }
            zigzag?.dwellSeconds = dwellSeconds
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
            let holding = watchEmpty()
            guard !holding else { return }
            if checkPresetEmptyWalk() { return }
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
                if trackingNow == .tracking, presetEmptyWalk == nil, let seen = lastTracked,
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
                    countingColumn = column
                    engine.setExternalCounting(active: true, column: column)
                    engine.logEvent("preset_path_column", detail: "\(column) at \(angleX),\(angleY)")
                case .columnEnded(let column):
                    endPresetEmptyWalk("edge")  // the leg ended inside the empty patch
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
                moveCheck = (servo, servo == .x ? angleX : angleY, seen.position, false, nil)
            }
            return true
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
            let holding = watchEmpty()
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
            guard !holding else { return }
            guard let mapping, !inFlight, Date().timeIntervalSince(lastSettledAt) >= 0.3,
                let dx = engine.guideInfo.steerDx, let dy = engine.guideInfo.steerDy
            else { return }
            // The guide's axes may be the straightened picture's; the servos were measured raw.
            let target = unstraightened(CGPoint(x: dx, y: dy))
            if hypot(Double(target.x), Double(target.y)) > 0 { lastSteer = target }
            var planner = StageMotionPlanner(mapping: mapping, chunkDegrees: chunkDegrees)
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
#endif
