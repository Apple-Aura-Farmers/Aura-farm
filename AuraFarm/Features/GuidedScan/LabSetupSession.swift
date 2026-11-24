import CoreGraphics
import CoreVideo
import Foundation
import Observation

/// What the run monitor made of one frame, for the screen and the CSV.
struct RunMonitorInfo: Equatable {
    var state = RunMonitorState.ok
    var focusIndex: Double?
    var focusBaseline: Double?
    /// The circle's centre shift (share of the confirmed radius) and radius change.
    var circleShift: Double?
    var circleRadiusChange: Double?
    /// The circle the run started with (frame px): drawn in orange while paused for
    /// alignment, so the phone can be lined up with it.
    var circle: FieldCircle?
    /// Focus is clearly low: the guide holds off capturing a spot.
    var focusLow = false
    /// Detail was lost while still (see `RunMonitor.isStillOnset`).
    var focusStillOnset = false
    /// While paused for focus with a baseline: the two-sided dial (value: the focus index).
    var dial: FocusDialReading?
    /// The sharpness reference and the latest reading over it; why the run is paused.
    var sharpnessReference: Double?
    var sharpnessShare: Double?
    var pauseCause = ""
    /// While paused for focus: the highest index so far and which way to turn. `resumedNote` is
    /// set for the one frame on which the pause ended by itself.
    var focusPeak: Double?
    var focusHint: String?
    var resumedNote = ""
    /// The latest focus index, also on the frames between readings; nil when it is too old.
    var recentFocusIndex: Double?
    /// The focus tiles: this frame's reading (nil between readings, for the log) and the latest
    /// one (for the lab's readout). Nothing decides with them.
    var focusTiles: FocusTilesReading?
    var focusTilesMilliseconds: Double?
    var recentFocusTiles: FocusTilesReading?
}

/// What the setup screens draw, published by the lab at its normal throttle.
struct LabSetupInfo: Equatable {
    var step = LabSetupStep.align
    var frameSize = CGSize.zero
    var alignment = AlignmentReading()
    var trend = AlignmentTrend.steady
    var isAlignmentPassed = false
    var focus: FocusReading?
    /// The two-sided dial, once the focus peak has been passed.
    var focusDial: FocusDialReading?
    /// The square the focus is measured in, frame pixels.
    var focusSquare: CGRect?
    /// The focus tiles on this frame, for the log and the readout only.
    var focusTiles: FocusTilesReading?
    /// The round view the focus is measured in, frame pixels; nil outside the focus step.
    var focusCircle: FieldCircle?
    /// Where setup goes after align passes again, when alignment was lost; nil otherwise.
    var resumeStep: LabSetupStep?
    /// The stage step's progress, and the measured axes once known (the identity when
    /// the step was skipped).
    var stage: StageAxesProgress?
    var stageAxes: StageAxes?
    var monitor = RunMonitorInfo()
    /// The focus step was finished in this setup (not skipped). The automated stage does not
    /// calibrate before it.
    var focusFound = false
}

/// The focus meter's value, published on every analyzed frame; a value of its own so only
/// the meter redraws that often. Main queue only.
@Observable
final class FocusMeterState {
    private(set) var reading: FocusReading?
    private(set) var dial: FocusDialReading?

    func update(_ reading: FocusReading?, dial: FocusDialReading? = nil) {
        if self.reading != reading { self.reading = reading }
        if self.dial != dial { self.dial = dial }
    }
}

/// The setup of a lab session: 1 align the phone, 2 field (find the eyepiece), 3 focus, 4 stage.
/// While the step is align or focus no frame goes to the pipeline, so nothing tracks; reaching
/// field starts learning the mask, with review, exactly as the lab does without setup. Focus
/// then runs inside the confirmed round view. At the stage step the tracker runs again and the
/// two knobs' axes are measured. After setup the same frames feed the run monitor.
///
/// Alignment lost after it passed sends setup back to align and then to the field step, which
/// learns the mask again (see `LabSetupFlow.alignmentLost`); focus follows, and a focus that
/// was already found stays found. Analysis queue only.
final class LabSetupSession {
    enum Output {
        /// An align or focus frame: the setup's state.
        case setup(LabSetupInfo)
        /// A field, stage or lab frame, which went through the pipeline.
        case tracked(SlideMovementStep)
    }

    private(set) var flow: LabSetupFlow
    private(set) var info = LabSetupInfo()
    private(set) var log: [SetupLogRow] = []
    /// The axes the picture and the guide are straightened with; nil until the stage step is
    /// done or skipped.
    private(set) var stageAxes: StageAxes?
    /// How long the last run-monitor alignment measurement took, in milliseconds.
    private(set) var alignmentMilliseconds = 0.0
    /// How long the last focus index took, in milliseconds.
    private(set) var focusIndexMilliseconds = 0.0

    private var alignment = AlignmentCheck()
    private var focus = FocusGuide()
    private var focusDial = LabSetupSession.newSetupDial()
    private var runDial: FocusDial?
    /// The run dial's latest reading, before it is matched to the monitor's verdict.
    private var runDialReading: FocusDialReading?
    /// The latest focus index measured during the run (at `lastRunFocusAt`).
    private var lastRunFocusIndex: Double?
    private var calibration = StageAxesCalibration()
    private var monitor = RunMonitor()
    private var lastPassingCircle: FieldCircle?
    private var referenceCircle: FieldCircle?
    private var latestAlignment = AlignmentReading()
    private var focusIndexes: [(seconds: Double, value: Double)] = []
    private var focusWasFocused = false
    /// See `LabSetupInfo.focusFound`.
    private var focusFound = false
    /// Since when a focus already found has read well below its peak again.
    private var focusFadedSince: Double?
    /// A found focus that stays under `FocusThresholds.passedFraction` of its peak this long, before
    /// it is confirmed, is lost: the focus guide starts afresh. PLACEHOLDER.
    static let focusFadedSeconds = 1.0
    /// Alignment was lost after it passed: the field is learned again, and a focus already found
    /// before the loss stays found when focus comes round again.
    private var resumingAfterLoss = false
    /// The guided scan page asks the person to confirm align and focus (as the field review is
    /// confirmed): the checks must pass AND the person must confirm before the step moves on. The
    /// lab leaves this off and advances as soon as the checks pass.
    var confirmsSteps = false
    /// Setup is held where it is (the guided scan before a stage is chosen and connected, the lab
    /// while it waits for the stage): no step advances and a confirmation is ignored. The camera
    /// and the overlays carry on.
    var isHeld = false
    private var stepConfirmed = false
    /// See `acceptFocus`.
    private var personSaysSharp = false
    /// The round view the person confirmed, which focus is measured inside.
    private var confirmedFieldCircle: FieldCircle?
    private var frameCounter = 0
    /// When the run monitor last took a focus index and an alignment reading; nil outside the run.
    private var lastRunFocusAt: Double?
    /// The focus tiles are read about three times a second, like the focus index.
    private var lastTilesAt: Double?
    private var recentTiles: FocusTilesReading?
    private var lastRunAlignmentAt: Double?
    private var origin: Double?
    private let gridStep = FieldMaskThresholds().gridStep
    /// The side of the focus square as a share of the circle's diameter. PLACEHOLDER: the
    /// middle of the circle holds the sample the helper looks at, not the rim.
    static let focusSquareShare = 0.7
    /// The run monitor measures alignment on every Nth analyzed frame. PLACEHOLDER: about
    /// 3 a second; the circle does not move faster than that matters.
    static let alignmentEveryNthFrame = 3
    /// After setup the run monitor measures by time, not by frame count: the focus index at most
    /// this often. PLACEHOLDER: about 3 a second.
    static let runFocusIntervalSeconds = 1.0 / 3.0
    /// ...and the alignment geometry at most this often. PLACEHOLDER.
    static let runAlignmentIntervalSeconds = 1.0
    /// The focus index of the setup's focus step is the median of this many seconds before
    /// "focused".
    static let baselineSeconds = 2.0

    init(skippingAlignAndFocus: Bool = false) {
        flow = LabSetupFlow(skippingAlignAndFocus: skippingAlignAndFocus)
        info.step = flow.step
    }

    var step: LabSetupStep { flow.step }

    /// The run monitor's focus baseline: set when the focus step finishes.
    var focusBaseline: Double? { monitor.focusBaseline }

    /// Focus is clearly low, for the guide to hold off a capture.
    var isFocusLow: Bool { info.monitor.focusLow }

    /// The stage is moved by hand (see `StageHandHold`). Analysis queue.
    private(set) var handHold = StageHandHold.off

    /// While `.on` the monitor sees a blank view and no focus index, so focus neither pauses nor
    /// resumes, and alignment is still watched. Entering it ends a pause for focus and keeps the
    /// baseline.
    func setHandHold(_ hold: StageHandHold) {
        handHold = hold
        guard hold == .on else { return }
        monitor.endFocusPauseForHand()
        runDial = nil
        runDialReading = nil
        if info.monitor.state == .pausedFocus {
            info.monitor.state = .ok
            info.monitor.pauseCause = ""
            info.monitor.dial = nil
        }
        info.monitor.focusLow = false
    }

    /// The run monitor's state, for the guide to pause on.
    var monitorState: RunMonitorState { info.monitor.state }

    /// The person confirmed the align or focus step they are on (see `confirmsSteps`).
    func confirmStep() {
        guard !isHeld else { return }
        stepConfirmed = true
    }

    /// The person says the picture is sharp although the checks have not found it so: the focus
    /// step moves on.
    func acceptFocus() {
        guard !isHeld, flow.step == .focus else { return }
        personSaysSharp = true
    }

    /// Back to align: the checks start afresh and the stage is forgotten.
    func redo() {
        skipsAllChecks = false
        stepConfirmed = false
        flow.redo()
        alignment.reset()
        resetFocus()
        calibration.reset()
        monitor.reset()
        monitor.setFocusBaseline(nil)
        lastPassingCircle = nil
        referenceCircle = nil
        confirmedFieldCircle = nil
        resumingAfterLoss = false
        focusWasFocused = false
        focusFound = false
        stageAxes = nil
        focusIndexes = []
        info = LabSetupInfo(step: .align, frameSize: info.frameSize)
    }

    /// Back to the field step, learning the eyepiece mask afresh.
    func redoField(pipeline: SlideMovementPipeline) {
        flow.redoField()
        enterField(pipeline: pipeline)
        info.step = .field
        info.resumeStep = nil
        info.stage = nil
    }

    /// "Skip setup": straight to done with no stage measured, and the run monitor never checks
    /// alignment or focus. `redo` brings the checks back.
    private(set) var skipsAllChecks = false

    func skipEverything() {
        flow.skip()
        stageAxes = .identity
        info.step = .done
        info.resumeStep = nil
        info.stageAxes = .identity
        info.monitor = RunMonitorInfo(circle: nil)
        skipsAllChecks = true
    }

    /// The helper skips the stage step: the picture and the guide stay as they are.
    func skipStage() {
        guard flow.step == .stage else { return }
        flow.skip()
        stageAxes = .identity
        info.step = .done
        info.stageAxes = .identity
    }

    /// Back to the stage step to be measured again, as a normal start would: the old axes and
    /// the monitor's pauses are gone; the focus baseline and focusFound are kept.
    func reopenStage() {
        // After "Skip setup" too: skipsAllChecks stays true, so no focus or alignment pause comes
        // back, and the stage step does not watch alignment.
        guard flow.step == .done else { return }
        flow.reopenStage()
        calibration.reset()
        stageAxes = nil
        monitor.reset()  // keeps the focus baseline
        runDial = nil
        runDialReading = nil
        info.step = .stage
        info.stageAxes = nil
        info.monitor = RunMonitorInfo(circle: referenceCircle)
    }

    /// The automated stage measured the axes itself: the step is done with them.
    func completeStage(with axes: StageAxes) {
        guard flow.step == .stage else { return }
        flow.update(stageMeasured: true)
        stageAxes = axes
        info.step = flow.step
        info.stageAxes = axes
    }

    /// - Parameters:
    ///   - guidePosition: where the view is, in the guide's screen fields (the dry run's
    ///     conversion), which the stage step measures the axes from.
    ///   - viewClass: what the box looked like on the last frame, for the monitor's focus
    ///     check; `.blank` ignores focus.
    ///   - isStill: the helper is not moving the slide; only still readings count for focus.
    ///   - stillSeconds: how long it has been still, for the setup log.
    func process(
        _ buffer: CVPixelBuffer, seconds: Double, pipeline: SlideMovementPipeline,
        measureAgreement: Bool,
        guidePosition: (SlideMovementStep) -> CGPoint = { $0.positionFields },
        viewClass: ViewClass = .blank, isStill: Bool = true, stillSeconds: Double = 0
    ) -> Output? {
        switch flow.step {
        case .align, .focus:
            return processSetup(buffer, seconds: seconds, pipeline: pipeline).map { .setup($0) }
        case .field, .stage, .done:
            guard
                let step = pipeline.process(
                    buffer, seconds: seconds, measureAgreement: measureAgreement)
            else { return nil }
            processTracked(
                step, buffer, seconds: seconds, pipeline: pipeline, guidePosition: guidePosition,
                viewClass: viewClass, isStill: isStill, stillSeconds: stillSeconds)
            return .tracked(step)
        }
    }

    // MARK: Align and focus

    private func processSetup(
        _ buffer: CVPixelBuffer, seconds: Double, pipeline: SlideMovementPipeline
    ) -> LabSetupInfo? {
        guard let grid = LumaGrid.sample(of: buffer, step: gridStep) else { return nil }
        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        alignment.confirmedCircle = flow.step == .focus ? confirmedFieldCircle : nil
        let reading = alignment.update(
            luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
            gridStep: gridStep, seconds: seconds)
        latestAlignment = reading
        if reading.passes { lastPassingCircle = reading.circle }

        var focusReading: FocusReading?
        var dialReading: FocusDialReading?
        var square: CGRect?
        var tilesReading: FocusTilesReading?
        // Measured inside the confirmed round view; the alignment's circle until there is one.
        if flow.step == .focus, let circle = confirmedFieldCircle ?? lastPassingCircle {
            let box = Self.focusSquare(for: circle, frameSize: frameSize)
            square = box
            if let sharpness = FrameAnalyzer.stats(of: buffer, in: box, step: 4)?.sharpness {
                focusReading = focus.update(sharpness: sharpness, seconds: seconds)
                if focusHasFaded(focusReading, seconds) {
                    // The knob was turned away again, or (after an alignment loss) the picture is
                    // not the one that was found sharp: found no longer.
                    resetFocus()
                    stepConfirmed = false
                    focusReading = focus.update(sharpness: sharpness, seconds: seconds)
                }
                focusWasFocused = focusReading?.state == .focused
                // The dial follows from the start, so it knows the side once it shows: after
                // the peak has been passed once.
                if let current = focusReading?.current {
                    let dial = focusDial.update(value: current, seconds: seconds)
                    if let state = focusReading?.state, state != .turnOneWay, state != .needsSample {
                        dialReading = dial
                    }
                }
            }
            if let index = FrameAnalyzer.focusIndex(of: buffer, in: box) {
                focusIndexes.append((seconds, index))
                focusIndexes.removeAll { seconds - $0.seconds > Self.baselineSeconds }
            }
            // Measured and logged, nothing more.
            if Self.isDue(lastTilesAt, now: seconds, interval: Self.runFocusIntervalSeconds) {
                lastTilesAt = seconds
                tilesReading = FocusTiles.measure(of: buffer, in: box)
            }
        }
        let atStep = flow.step
        let start = origin ?? seconds
        origin = start
        appendLog(
            SetupLogRow(
                seconds: seconds - start, step: atStep, alignment: reading, focus: focusReading,
                focusDial: dialReading, focusTiles: tilesReading))

        if atStep == .align {
            if flow.update(alignmentPassed: alignment.isPassed && canAdvance) {
                stepConfirmed = false
                enterField(pipeline: pipeline)
            }
        } else if alignment.isLost {
            stepConfirmed = false
            flow.alignmentLost()
            alignment.reset()
            resumingAfterLoss = true
            focusReading = nil
        } else if flow.update(
            focused: personSaysSharp && !isHeld
                || focusReading?.state == .focused && focusFadedSince == nil && canAdvance)
        {
            stepConfirmed = false
            personSaysSharp = false
            focusFound = true
            monitor.setFocusBaseline(median(focusIndexes.map(\.value)))
            // Tracking starts afresh for the stage step: the picture is sharper than the anchor
            // the field step left.
            pipeline.resetPosition()
        }
        info = LabSetupInfo(
            step: flow.step, frameSize: frameSize, alignment: reading, trend: alignment.trend,
            isAlignmentPassed: alignment.isPassed, focus: focusReading, focusDial: dialReading,
            focusSquare: square, focusTiles: tilesReading,
            focusCircle: flow.step == .focus ? confirmedFieldCircle ?? lastPassingCircle : nil,
            resumeStep: flow.resumeStep)
        info.focusFound = focusFound
        return info
    }

    /// The step may move on: always in the lab, after the person's confirmation on the page.
    private var canAdvance: Bool { !isHeld && (!confirmsSteps || stepConfirmed) }

    /// A focus that was found has read well below its peak for `focusFadedSeconds`.
    private func focusHasFaded(_ reading: FocusReading?, _ seconds: Double) -> Bool {
        guard let reading, reading.state == .focused,
            reading.level < focus.thresholds.passedFraction
        else {
            focusFadedSince = nil
            return false
        }
        let since = focusFadedSince ?? seconds
        focusFadedSince = since
        return seconds - since >= Self.focusFadedSeconds - 1e-9
    }

    private static func newSetupDial() -> FocusDial {
        FocusDial(
            target: nil, goodShare: FocusThresholds().nearFraction, raisesTarget: true)
    }

    private func resetFocus() {
        focus.reset()
        focusFadedSince = nil
        focusDial = Self.newSetupDial()
    }

    /// Reaching field (from align, or back to it) learns the mask afresh, with review.
    private func enterField(pipeline: SlideMovementPipeline) {
        pipeline.redetectField()
        calibration.reset()
        monitor.reset()
        stageAxes = nil
        referenceCircle = lastPassingCircle
        confirmedFieldCircle = nil
        focusFound = false
    }

    /// Focus is about to run (the field was confirmed): a focus found before an alignment loss
    /// stays found, otherwise the focus guide starts afresh.
    private func enterFocus() {
        stepConfirmed = false
        personSaysSharp = false
        if !(resumingAfterLoss && focusWasFocused) {
            resetFocus()
            focusWasFocused = false
        }
        resumingAfterLoss = false
    }

    // MARK: Field, stage and the run

    private func processTracked(
        _ step: SlideMovementStep, _ buffer: CVPixelBuffer, seconds: Double,
        pipeline: SlideMovementPipeline, guidePosition: (SlideMovementStep) -> CGPoint,
        viewClass: ViewClass, isStill: Bool, stillSeconds: Double
    ) {
        frameCounter += 1
        let tracking = step.tracking.trackingState
        var reading: AlignmentReading?
        let inRun = flow.step == .done
        if !inRun {
            lastRunFocusAt = nil
            lastTilesAt = nil
            recentTiles = nil
            lastRunFocusIndex = nil
            lastRunAlignmentAt = nil
        }
        let alignmentDue =
            inRun
            ? Self.isDue(lastRunAlignmentAt, now: seconds, interval: Self.runAlignmentIntervalSeconds)
            : frameCounter % Self.alignmentEveryNthFrame == 0
        if alignmentDue,
            let grid = LumaGrid.sample(of: buffer, step: gridStep)
        {
            let started = ContinuousClock.now
            let measured = AlignmentMeasure.measure(
                luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                gridStep: gridStep, thresholds: AlignmentThresholds())
            alignmentMilliseconds = Self.milliseconds(since: started)
            reading = measured
            latestAlignment = measured
            if inRun { lastRunAlignmentAt = seconds }
        }
        var progress = info.stage
        let atStep = flow.step

        switch atStep {
        case .field:
            if step.fieldState?.mask != nil, !step.awaitingReview, !isHeld {
                // Confirmed: the circle the run is held to is the one measured now, by the
                // same method that will watch it.
                if latestAlignment.found { referenceCircle = latestAlignment.circle }
                confirmedFieldCircle = step.fieldState?.mask.flatMap { FieldCircle(fitting: $0) }
                calibration.reset()
                monitor.reset()
                if flow.update(fieldConfirmed: true), flow.step == .focus { enterFocus() }
            } else {
                watchAlignment(reading, tracking: tracking, seconds: seconds)
            }
        case .stage:
            let moved = calibration.update(
                position: guidePosition(step), tracking: tracking, seconds: seconds)
            progress = moved
            if moved.step == .done {
                stageAxes = calibration.result
                flow.update(stageMeasured: true)
            } else if !skipsAllChecks {
                watchAlignment(reading, tracking: tracking, seconds: seconds)
            }
        case .done:
            monitorRun(
                step, buffer, reading: reading, tracking: tracking, viewClass: viewClass,
                isStill: isStill,
                seconds: seconds)
        case .align, .focus:
            break
        }

        if atStep == .stage || atStep == .field {
            let start = origin ?? seconds
            origin = start
            appendLog(
                SetupLogRow(
                    seconds: seconds - start, step: atStep, alignment: latestAlignment,
                    focus: nil, stage: atStep == .stage ? progress : nil,
                    stageAxes: stageAxes,
                    tracker: SetupTrackerSample(
                        tracking: tracking, position: guidePosition(step),
                        boxSharpness: step.boxStats.sharpness, viewClass: viewClass,
                        stillSeconds: stillSeconds,
                        featureCells: step.tracking.featureCells)))
        }
        info.step = flow.step
        info.focusFound = focusFound
        info.frameSize = step.frameSize
        info.resumeStep = flow.resumeStep
        info.stage = flow.step == .stage || flow.step == .done ? progress : nil
        info.stageAxes = stageAxes
        if flow.step != .done { info.monitor = RunMonitorInfo(circle: referenceCircle) }
        if flow.step == .done { measureRunTiles(buffer, seconds: seconds) }
    }

    /// The focus tiles of the run, about three times a second, whatever the monitor is doing
    /// (paused for focus, held for the hand, after Skip setup). For the log and the lab's readout
    /// only: no decision reads them.
    private func measureRunTiles(_ buffer: CVPixelBuffer, seconds: Double) {
        var fresh: FocusTilesReading?
        var milliseconds: Double?
        if let circle = confirmedFieldCircle ?? referenceCircle,
            Self.isDue(lastTilesAt, now: seconds, interval: Self.runFocusIntervalSeconds)
        {
            lastTilesAt = seconds
            let size = CGSize(
                width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            let started = ContinuousClock.now
            fresh = FocusTiles.measure(of: buffer, in: Self.focusSquare(for: circle, frameSize: size))
            milliseconds = Self.milliseconds(since: started)
            if let fresh { recentTiles = fresh }
        }
        info.monitor.focusTiles = fresh
        info.monitor.focusTilesMilliseconds = fresh == nil ? nil : milliseconds
        info.monitor.recentFocusTiles = recentTiles
    }

    /// Field and stage: the geometry-only check; lost alignment goes back to align.
    private func watchAlignment(
        _ reading: AlignmentReading?, tracking: TrackingState, seconds: Double
    ) {
        guard reading != nil else { return }
        let state = monitor.update(
            alignment: reading, confirmedCircle: referenceCircle, focusIndex: nil,
            viewClass: .blank, tracking: tracking, seconds: seconds)
        guard state == .pausedAlignment else { return }
        flow.alignmentLost()
        alignment.reset()
        monitor.reset()
        stepConfirmed = false
        resumingAfterLoss = true
    }

    /// Whether `interval` seconds have passed since `last` (always, if there was none).
    private static func isDue(_ last: Double?, now: Double, interval: Double) -> Bool {
        guard let last else { return true }
        return now - last >= interval - 1e-9
    }

    /// After setup: geometry once a second and the focus index three times a second, by the
    /// readings' own clock; box sharpness goes in on every frame.
    private func monitorRun(
        _ step: SlideMovementStep, _ buffer: CVPixelBuffer, reading: AlignmentReading?,
        tracking: TrackingState, viewClass: ViewClass, isStill: Bool, seconds: Double
    ) {
        guard !skipsAllChecks else { return }
        let held = handHold == .on
        let viewClass = held ? ViewClass.blank : viewClass
        var index: Double?
        if !held, let box = step.registrationRect,
            Self.isDue(lastRunFocusAt, now: seconds, interval: Self.runFocusIntervalSeconds)
        {
            lastRunFocusAt = seconds
            let started = ContinuousClock.now
            index = FrameAnalyzer.focusIndex(of: buffer, in: box)
            lastRunFocusIndex = index
            focusIndexMilliseconds = Self.milliseconds(since: started)
        }
        let state = monitor.update(
            alignment: reading, confirmedCircle: referenceCircle, focusIndex: index,
            boxSharpness: step.boxStats.sharpness, viewClass: viewClass, tracking: tracking,
            isStill: isStill, seconds: seconds)
        if state == .pausedFocus, let index {
            // Paused for focus: from the first reading, a dial against the baseline (words
            // only without one). The Z knob does not move the slide, so still or not.
            if runDial == nil, let baseline = monitor.focusBaseline, baseline > 0 {
                runDial = FocusDial(
                    target: baseline, goodShare: RunMonitorThresholds().resumeAtShareOfBaseline,
                    startsUnknown: true)
            }
            runDialReading = runDial?.update(value: index, seconds: seconds)
        } else if state != .pausedFocus {
            runDial = nil
            runDialReading = nil
        }
        // Between focus readings the needle stays as it was. Green exactly when the monitor counts
        // the view as sharp (judged on every frame), so the two never disagree.
        let dial = runDialReading?.matching(isSharp: monitor.isSharp)
        let focusIsRecent =
            lastRunFocusAt.map { seconds - $0 <= RunMonitorThresholds().focusReadingGapSeconds } ?? false
        info.monitor = RunMonitorInfo(
            state: state, focusIndex: index, focusBaseline: monitor.focusBaseline,
            circleShift: reading == nil ? nil : monitor.circleShift,
            circleRadiusChange: reading == nil ? nil : monitor.circleRadiusChange,
            circle: referenceCircle, focusLow: monitor.isFocusLow,
            focusStillOnset: monitor.isStillOnset, dial: dial,
            sharpnessReference: monitor.sharpnessReference,
            sharpnessShare: monitor.sharpnessShare, pauseCause: monitor.pauseCause,
            focusPeak: monitor.peakIndex, focusHint: monitor.focusHint,
            resumedNote: monitor.resumeNote, recentFocusIndex: focusIsRecent ? lastRunFocusIndex : nil)
    }

    /// "Resume anyway": the run goes on at once and the focus baseline is measured again from
    /// the next readings. Analysis queue.
    @discardableResult
    func resumeFocusManually() -> Bool {
        guard monitor.state == .pausedFocus else { return false }
        monitor.resumeManually()
        runDial = nil
        runDialReading = nil
        info.monitor.state = .ok
        info.monitor.focusBaseline = nil
        info.monitor.focusLow = false
        info.monitor.dial = nil
        info.monitor.pauseCause = ""
        return true
    }

    /// Pauses the run for focus from outside (a stall the monitor has not caught); false when it
    /// is already paused. Analysis queue.
    @discardableResult
    func requestFocusPause() -> Bool {
        // After "Skip setup" nothing is measured, so a pause could never end.
        guard flow.step == .done, !skipsAllChecks, monitor.pauseForStall() else { return false }
        info.monitor.state = monitor.state
        info.monitor.pauseCause = monitor.pauseCause
        return true
    }

    /// The focus baseline is measured again from the next readings; the monitor's state stays.
    func remeasureFocusBaseline() {
        monitor.setFocusBaseline(nil)
        info.monitor.focusBaseline = nil
    }

    /// Starts afresh when the person marks the start of a run: counts cleared, and with no
    /// setup baseline the focus baseline is collected from the next readings.
    func rearmMonitor() {
        monitor.reset()
        runDial = nil
        info.monitor.state = .ok
    }

    // MARK: Helpers

    /// A square of `focusSquareShare` of the circle's diameter, centred on it, kept inside
    /// the frame.
    static func focusSquare(for circle: FieldCircle, frameSize: CGSize) -> CGRect {
        let side = circle.radius * 2 * focusSquareShare
        let box = CGRect(
            x: circle.centre.x - side / 2, y: circle.centre.y - side / 2, width: side,
            height: side)
        return box.intersection(CGRect(origin: .zero, size: frameSize))
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let taken = ContinuousClock.now - start
        return Double(taken.components.seconds) * 1000
            + Double(taken.components.attoseconds) / 1e15
    }

    private func appendLog(_ row: SetupLogRow) {
        log.append(row)
        while let first = log.first, row.seconds - first.seconds > SetupLog.keepSeconds {
            log.removeFirst()
        }
    }
}
