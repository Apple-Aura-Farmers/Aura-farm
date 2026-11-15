#if DEBUG
    import CoreGraphics
    import CoreVideo
    import Foundation
    import Observation

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

    /// The setup of a lab session: 1 align the phone, 2 focus, 3 field. While the step is align
    /// or focus no frame goes to the pipeline, so nothing learns the mask and nothing tracks;
    /// reaching field starts learning it, with review, exactly as the lab does without setup.
    /// Analysis queue only.
    final class LabSetupSession {
        enum Output {
            /// An align or focus frame: the setup's state.
            case setup(LabSetupInfo)
            /// A field or lab frame, which went through the pipeline.
            case tracked(SlideMovementStep)
        }

        private(set) var flow: LabSetupFlow
        private(set) var info = LabSetupInfo()
        private(set) var log: [SetupLogRow] = []

        private var alignment = AlignmentCheck()
        private var focus = FocusGuide()
        private var lastPassingCircle: FieldCircle?
        private var origin: Double?
        private let gridStep = FieldMaskThresholds().gridStep
        /// The side of the focus square as a share of the circle's diameter. PLACEHOLDER: the
        /// middle of the circle holds the sample the helper looks at, not the rim.
        static let focusSquareShare = 0.7

        init(skippingAlignAndFocus: Bool = false) {
            flow = LabSetupFlow(skippingAlignAndFocus: skippingAlignAndFocus)
            info.step = flow.step
        }

        var step: LabSetupStep { flow.step }

        /// Back to align: the checks start afresh.
        func redo() {
            flow.redo()
            alignment.reset()
            focus.reset()
            lastPassingCircle = nil
            info = LabSetupInfo(step: .align, frameSize: info.frameSize)
        }

        /// Back to the field step, learning the eyepiece mask afresh.
        func redoField(pipeline: SlideMovementPipeline) {
            flow.redoField()
            info.step = .field
            pipeline.redetectField()
        }

        func process(
            _ buffer: CVPixelBuffer, seconds: Double, pipeline: SlideMovementPipeline,
            measureAgreement: Bool
        ) -> Output? {
            switch flow.step {
            case .align, .focus:
                return processSetup(buffer, seconds: seconds, pipeline: pipeline).map { .setup($0) }
            case .field, .done:
                guard
                    let step = pipeline.process(
                        buffer, seconds: seconds, measureAgreement: measureAgreement)
                else { return nil }
                if flow.step == .field, step.fieldState?.mask != nil, !step.awaitingReview {
                    flow.update(fieldConfirmed: true)
                }
                info.step = flow.step
                return .tracked(step)
            }
        }

        private func processSetup(
            _ buffer: CVPixelBuffer, seconds: Double, pipeline: SlideMovementPipeline
        ) -> LabSetupInfo? {
            guard let grid = LumaGrid.sample(of: buffer, step: gridStep) else { return nil }
            let frameSize = CGSize(
                width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            let reading = alignment.update(
                luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                gridStep: gridStep, seconds: seconds)
            if reading.passes { lastPassingCircle = reading.circle }

            var focusReading: FocusReading?
            var square: CGRect?
            if flow.step == .focus, let circle = lastPassingCircle {
                let box = Self.focusSquare(for: circle, frameSize: frameSize)
                square = box
                if let sharpness = FrameAnalyzer.stats(of: buffer, in: box, step: 4)?.sharpness {
                    focusReading = focus.update(sharpness: sharpness, seconds: seconds)
                }
            }
            let atStep = flow.step
            let start = origin ?? seconds
            origin = start
            appendLog(
                SetupLogRow(
                    seconds: seconds - start, step: atStep, alignment: reading, focus: focusReading))

            if atStep == .align {
                if flow.update(alignmentPassed: alignment.isPassed) { focus.reset() }
            } else if flow.update(focused: focusReading?.state == .focused) {
                // Reaching field starts learning the mask, with review.
                pipeline.redetectField()
            }
            info = LabSetupInfo(
                step: flow.step, frameSize: frameSize, alignment: reading, trend: alignment.trend,
                isAlignmentPassed: alignment.isPassed, focus: focusReading, focusSquare: square)
            return info
        }

        /// A square of `focusSquareShare` of the circle's diameter, centred on it, kept inside
        /// the frame.
        static func focusSquare(for circle: FieldCircle, frameSize: CGSize) -> CGRect {
            let side = circle.radius * 2 * focusSquareShare
            let box = CGRect(
                x: circle.centre.x - side / 2, y: circle.centre.y - side / 2, width: side,
                height: side)
            return box.intersection(CGRect(origin: .zero, size: frameSize))
        }

        private func appendLog(_ row: SetupLogRow) {
            log.append(row)
            while let first = log.first, row.seconds - first.seconds > SetupLog.keepSeconds {
                log.removeFirst()
            }
        }
    }
#endif
