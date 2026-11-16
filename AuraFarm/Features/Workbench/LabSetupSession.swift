#if DEBUG
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
    }

    /// What the setup screens draw, published by the lab at its normal throttle.
    struct LabSetupInfo: Equatable {
        var step = LabSetupStep.align
        var frameSize = CGSize.zero
        var alignment = AlignmentReading()
        var trend = AlignmentTrend.steady
        var isAlignmentPassed = false
        var focus: FocusReading?
        /// The square the focus is measured in, frame pixels.
        var focusSquare: CGRect?
        /// Where setup goes after align passes again, when alignment was lost; nil otherwise.
        var resumeStep: LabSetupStep?
        /// The stage step's progress, and the measured axes once known (the identity when
        /// the step was skipped).
        var stage: StageAxesProgress?
        var stageAxes: StageAxes?
        var monitor = RunMonitorInfo()
    }

    /// The focus meter's value, published on every analyzed frame; a value of its own so only
    /// the meter redraws that often. Main queue only.
    @Observable
    final class FocusMeterState {
        private(set) var reading: FocusReading?

        func update(_ reading: FocusReading?) {
            if self.reading != reading { self.reading = reading }
        }
    }

    /// The setup of a lab session: 1 align the phone, 2 focus, 3 field, 4 stage. While the step is
    /// align or focus no frame goes to the pipeline, so nothing learns the mask and nothing
    /// tracks; reaching field starts learning it, with review, exactly as the lab does without
    /// setup. At the stage step the tracker runs and the two knobs' axes are measured. After
    /// setup the same frames feed the run monitor.
    ///
    /// Alignment lost after it passed sends setup back to align and, once aligned again, on to
    /// where it was (see `LabSetupFlow.alignmentLost`). Analysis queue only.
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
        private var calibration = StageAxesCalibration()
        private var monitor = RunMonitor()
        private var lastPassingCircle: FieldCircle?
        private var referenceCircle: FieldCircle?
        private var latestAlignment = AlignmentReading()
        private var focusIndexes: [(seconds: Double, value: Double)] = []
        private var focusWasFocused = false
        private var frameCounter = 0
        private var origin: Double?
        private let gridStep = FieldMaskThresholds().gridStep
        /// The side of the focus square as a share of the circle's diameter. PLACEHOLDER: the
        /// middle of the circle holds the sample the helper looks at, not the rim.
        static let focusSquareShare = 0.7
        /// The run monitor measures alignment on every Nth analyzed frame. PLACEHOLDER: about
        /// 3 a second; the circle does not move faster than that matters.
        static let alignmentEveryNthFrame = 3
        /// The focus index of the setup's focus step is the median of this many seconds before
        /// "focused".
        static let baselineSeconds = 2.0

        init(skippingAlignAndFocus: Bool = false) {
            flow = LabSetupFlow(skippingAlignAndFocus: skippingAlignAndFocus)
            info.step = flow.step
        }

        var step: LabSetupStep { flow.step }

        /// Focus is clearly low, for the guide to hold off a capture.
        var isFocusLow: Bool { info.monitor.focusLow }

        /// The run monitor's state, for the guide to pause on.
        var monitorState: RunMonitorState { info.monitor.state }

        /// Back to align: the checks start afresh and the stage is forgotten.
        func redo() {
            flow.redo()
            alignment.reset()
            focus.reset()
            calibration.reset()
            monitor.reset()
            monitor.setFocusBaseline(nil)
            lastPassingCircle = nil
            referenceCircle = nil
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

        /// The helper skips the stage step: the picture and the guide stay as they are.
        func skipStage() {
            guard flow.step == .stage else { return }
            flow.skip()
            stageAxes = .identity
            info.step = .done
            info.stageAxes = .identity
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
            let reading = alignment.update(
                luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                gridStep: gridStep, seconds: seconds)
            latestAlignment = reading
            if reading.passes { lastPassingCircle = reading.circle }

            var focusReading: FocusReading?
            var square: CGRect?
            if flow.step == .focus, let circle = lastPassingCircle {
                let box = Self.focusSquare(for: circle, frameSize: frameSize)
                square = box
                if let sharpness = FrameAnalyzer.stats(of: buffer, in: box, step: 4)?.sharpness {
                    focusReading = focus.update(sharpness: sharpness, seconds: seconds)
                    focusWasFocused = focusReading?.state == .focused
                }
                if let index = FrameAnalyzer.focusIndex(of: buffer, in: box) {
                    focusIndexes.append((seconds, index))
                    focusIndexes.removeAll { seconds - $0.seconds > Self.baselineSeconds }
                }
            }
            let atStep = flow.step
            let start = origin ?? seconds
            origin = start
            appendLog(
                SetupLogRow(
                    seconds: seconds - start, step: atStep, alignment: reading, focus: focusReading))

            if atStep == .align {
                let resuming = flow.resumeStep
                if flow.update(alignmentPassed: alignment.isPassed) {
                    switch flow.step {
                    case .field: enterField(pipeline: pipeline)
                    case .focus where resuming == .focus:
                        // The knob did not move: a focus already found stays found.
                        if !focusWasFocused { focus.reset() }
                    default: focus.reset()
                    }
                }
            } else if alignment.isLost {
                flow.alignmentLost()
                alignment.reset()
                focusReading = nil
            } else if flow.update(focused: focusReading?.state == .focused) {
                monitor.setFocusBaseline(median(focusIndexes.map(\.value)))
                enterField(pipeline: pipeline)
            }
            info = LabSetupInfo(
                step: flow.step, frameSize: frameSize, alignment: reading, trend: alignment.trend,
                isAlignmentPassed: alignment.isPassed, focus: focusReading, focusSquare: square,
                resumeStep: flow.resumeStep)
            return info
        }

        /// Reaching field (from focus, or back to it) learns the mask afresh, with review.
        private func enterField(pipeline: SlideMovementPipeline) {
            pipeline.redetectField()
            calibration.reset()
            monitor.reset()
            stageAxes = nil
            referenceCircle = lastPassingCircle
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
            if frameCounter % Self.alignmentEveryNthFrame == 0,
                let grid = LumaGrid.sample(of: buffer, step: gridStep)
            {
                let started = ContinuousClock.now
                let measured = AlignmentMeasure.measure(
                    luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                    gridStep: gridStep, thresholds: AlignmentThresholds())
                alignmentMilliseconds = Self.milliseconds(since: started)
                reading = measured
                latestAlignment = measured
            }
            var progress = info.stage
            let atStep = flow.step

            switch atStep {
            case .field:
                if step.fieldState?.mask != nil, !step.awaitingReview {
                    // Confirmed: the circle the run is held to is the one measured now, by the
                    // same method that will watch it.
                    if latestAlignment.found { referenceCircle = latestAlignment.circle }
                    calibration.reset()
                    monitor.reset()
                    flow.update(fieldConfirmed: true)
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
                } else {
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
                            stillSeconds: stillSeconds)))
            }
            info.step = flow.step
            info.frameSize = step.frameSize
            info.resumeStep = flow.resumeStep
            info.stage = flow.step == .stage || flow.step == .done ? progress : nil
            info.stageAxes = stageAxes
            if flow.step != .done { info.monitor = RunMonitorInfo(circle: referenceCircle) }
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
        }

        /// After setup: geometry every 3rd frame, the focus index on every frame.
        private func monitorRun(
            _ step: SlideMovementStep, _ buffer: CVPixelBuffer, reading: AlignmentReading?,
            tracking: TrackingState, viewClass: ViewClass, isStill: Bool, seconds: Double
        ) {
            var index: Double?
            if let box = step.registrationRect {
                let started = ContinuousClock.now
                index = FrameAnalyzer.focusIndex(of: buffer, in: box)
                focusIndexMilliseconds = Self.milliseconds(since: started)
            }
            let state = monitor.update(
                alignment: reading, confirmedCircle: referenceCircle, focusIndex: index,
                boxSharpness: step.boxStats.sharpness, viewClass: viewClass, tracking: tracking,
                isStill: isStill, seconds: seconds)
            info.monitor = RunMonitorInfo(
                state: state, focusIndex: index, focusBaseline: monitor.focusBaseline,
                circleShift: monitor.circleShift, circleRadiusChange: monitor.circleRadiusChange,
                circle: referenceCircle, focusLow: monitor.isFocusLow,
                focusStillOnset: monitor.isStillOnset)
        }

        /// Starts afresh when the person marks the start of a run: counts cleared, and with no
        /// setup baseline the focus baseline is collected from the next readings.
        func rearmMonitor() {
            monitor.reset()
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
#endif
