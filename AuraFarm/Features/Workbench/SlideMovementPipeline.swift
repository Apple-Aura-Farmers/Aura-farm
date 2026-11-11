#if DEBUG
    import CoreImage
    import CoreVideo
    import Foundation

    /// What one analyzed frame told the slide movement lab.
    struct SlideMovementStep {
        var stats: FrameStats
        /// `ShakeEstimator.lastShift`: frame to frame, px.
        var shake: CGPoint?
        /// The live offset from the anchor after this frame, px. nil when this frame became
        /// the anchor or the registration gave nothing.
        var anchorOffset: CGPoint?
        var position: CGPoint
        var positionFrames: CGPoint
        var hops: Int
        var gaps: Int
        var isLost: Bool
        var event: HopOdometer.Event
        /// `PanoramaStitcher.agreement` at a hop, when it was measured.
        var hopAgreement: Double?
        var frameSize: CGSize
        /// Where learning the eyepiece mask has got to; nil unless the mode is Auto.
        var fieldState: FieldState?
        /// Where registration looked, in frame pixels; nil when it used the whole frame.
        var registrationRect: CGRect?
        var fieldMode: FieldRegionMode
        /// A tint of the learned mask for the overlay; set once the mask is decided.
        var maskImage: CGImage?
        /// How long this frame's analysis took, in milliseconds.
        var analysisMilliseconds: Double
        /// Analyzed frames per second over the last second.
        var analyzedFps: Double
        /// Whether the learned field is waiting for the person to confirm or adjust it.
        var awaitingReview = false

        var eventName: String {
            switch event {
            case .none: ""
            case .hop: "hop"
            case .lost: "lost"
            case .regained: "regained"
            }
        }

        /// The word written in the CSV's `field_region` column.
        var fieldRegionName: String {
            guard fieldMode.learnsMask else { return fieldMode.csvName }
            let prefix = fieldMode == .auto ? "auto" : "bright-region"
            switch fieldState {
            case .ready: return "\(prefix)-learned"
            case .untrusted: return "\(prefix)-untrusted"
            default: return "\(prefix)-learning"
            }
        }
    }

    /// The measurement chain of the slide movement lab: stats, shake, hop tracking. One
    /// instance per run; every call must come from the same serial queue (the analysis queue
    /// live, the reader's queue for a video).
    ///
    /// In Auto mode the first frames of a run only learn the eyepiece mask: no hops, no lost.
    ///
    /// Holds two frames at most: the anchor, and `ShakeEstimator`'s previous frame. The mask is
    /// learned from small copies of each frame's luma, never from the buffers themselves.
    final class SlideMovementPipeline {
        /// The least gap between two agreement measurements, in seconds. Measuring converts
        /// two frames to images and correlates them, which is far dearer than the rest of
        /// the chain, so it is rationed.
        static let agreementEverySeconds = 1.0
        /// The lab samples every 4th pixel for its statistics: coarser than the capture
        /// screen's 2, to keep a Debug build up with the camera. Sharpness read this way is NOT
        /// on the capture screen's scale.
        static let sampleStep = 4

        /// Where registration looks. Set from the analysis queue. Choosing Auto starts
        /// learning the mask.
        var fieldMode = FieldRegionMode.auto {
            didSet { if fieldMode != oldValue, fieldMode.learnsMask { restartLearning() } }
        }

        /// Where the mask has got to.
        private(set) var fieldState = FieldState.learning(progress: 0)

        private let maskThresholds: FieldMaskThresholds
        private let shake = ShakeEstimator()
        private let travel = TravelSinceLastFrame()
        private var odometer: HopOdometer
        /// The frame the travel is measured from. The same buffer `travel` holds, kept here
        /// as well because a hop's agreement needs both frames as images.
        private var anchor: CVPixelBuffer?
        private lazy var context = CIContext(options: [.useSoftwareRenderer: false])
        private var lastAgreementAt = -Double.infinity
        private var rate = FrameRateMeter()
        private var builder: FieldMaskBuilder?
        private var lastFrameSize = CGSize.zero

        /// When true, tracking waits after the mask is learned until `confirmField()`, so the
        /// person can check it (and adjust it with `adjustField`) first. The live lab sets it.
        var requiresReview = false
        private(set) var isAwaitingReview = false
        /// Where registration looks once the mode and the mask are settled, in frame pixels.
        private var registrationRect: CGRect?
        private var maskImage: CGImage?

        init(
            thresholds: HopOdometerThresholds = HopOdometerThresholds(),
            maskThresholds: FieldMaskThresholds = FieldMaskThresholds()
        ) {
            odometer = HopOdometer(thresholds: thresholds)
            self.maskThresholds = maskThresholds
        }

        /// Whether the eyepiece mask is still being learned.
        var isLearning: Bool {
            if case .learning = fieldState { return true }
            return false
        }

        /// Forgets the position and the anchor: the next frame anchors afresh. A mask that is
        /// still being learned starts again; one already learned is kept.
        func resetPosition() {
            clearTracking()
            if fieldMode.learnsMask, isLearning { restartLearning() }
        }

        /// The person is happy with the field: tracking starts afresh from the next frame.
        func confirmField() {
            guard isAwaitingReview else { return }
            isAwaitingReview = false
            clearTracking()
        }

        /// Replaces the learned field with a circle the person drew.
        func adjustField(to circle: FieldCircle) {
            guard fieldMode.learnsMask, lastFrameSize != .zero else { return }
            let mask = circle.clamped(to: lastFrameSize).mask(
                frameSize: lastFrameSize, thresholds: maskThresholds)
            fieldState = mask.isTrusted ? .ready(mask) : .untrusted(mask)
            maskImage = mask.tintImage()
            clearTracking()
        }

        /// Forgets the learned mask and learns it again.
        func redetectField() {
            restartLearning()
        }

        /// - Parameters:
        ///   - seconds: the frame's time, used to ration the agreement measurement and to time
        ///     the frame rate.
        ///   - measureAgreement: whether a hop may be checked against `PanoramaStitcher`.
        func process(
            _ buffer: CVPixelBuffer, seconds: Double, measureAgreement: Bool
        ) -> SlideMovementStep? {
            let started = ContinuousClock.now
            guard let stats = FrameAnalyzer.stats(of: buffer, step: Self.sampleStep) else {
                return nil
            }
            let frameSize = CGSize(
                width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            lastFrameSize = frameSize
            let learning =
                fieldMode.learnsMask && (learn(from: buffer, frameSize: frameSize) || isAwaitingReview)
            applyRegion(frameSize: frameSize)

            var offset: CGPoint?
            var event = HopOdometer.Event.none
            var agreement: Double?

            if !learning {
                _ = shake.update(with: buffer)
                if let held = anchor {
                    offset = travel.offset(to: buffer)
                    let result = odometer.update(offset: offset, frameSize: frameSize)
                    event = result.event
                    if event == .hop, measureAgreement, let offset,
                        seconds - lastAgreementAt >= Self.agreementEverySeconds
                    {
                        lastAgreementAt = seconds
                        agreement = self.agreement(from: held, to: buffer, offset: offset)
                    }
                    if result.reanchor { anchorOn(buffer) }
                } else {
                    // No anchor yet: anchor on this frame. Not a lost reading.
                    anchorOn(buffer)
                }
            }

            let shortSide = Double(min(frameSize.width, frameSize.height))
            let taken = ContinuousClock.now - started
            let milliseconds =
                Double(taken.components.seconds) * 1000
                + Double(taken.components.attoseconds) / 1e15
            let fps = rate.record(seconds)
            return SlideMovementStep(
                stats: stats,
                shake: learning ? nil : shake.lastShift,
                anchorOffset: offset,
                position: odometer.position,
                positionFrames: odometer.positionInFrames(shortSide: shortSide),
                hops: odometer.hops,
                gaps: odometer.gaps,
                isLost: odometer.isLost,
                event: event,
                hopAgreement: agreement,
                frameSize: frameSize,
                fieldState: fieldMode.learnsMask ? fieldState : nil,
                registrationRect: registrationRect,
                fieldMode: fieldMode,
                maskImage: fieldMode.learnsMask ? maskImage : nil,
                analysisMilliseconds: milliseconds,
                analyzedFps: fps, awaitingReview: isAwaitingReview)
        }

        // MARK: Field mask

        private func clearTracking() {
            odometer.reset()
            travel.reset()
            shake.reset()
            anchor = nil
        }

        private func restartLearning() {
            builder = nil
            isAwaitingReview = false
            fieldState = .learning(progress: 0)
            registrationRect = nil
            maskImage = nil
            clearTracking()
        }

        /// Auto learns over several frames with a slightly lowered cut; the bright-region mode
        /// decides from one frame at the plain automatic cut.
        private var learningThresholds: FieldMaskThresholds {
            guard fieldMode == .brightRegion else { return maskThresholds }
            var single = maskThresholds
            single.framesToLearn = 1
            single.cutScale = 1
            return single
        }

        /// Feeds the frame to the mask builder while learning. Returns whether this frame was
        /// spent learning (so it is not tracked).
        private func learn(from buffer: CVPixelBuffer, frameSize: CGSize) -> Bool {
            guard case .learning = fieldState else { return false }
            var builder =
                self.builder
                ?? FieldMaskBuilder(
                    width: Int(frameSize.width), height: Int(frameSize.height),
                    thresholds: learningThresholds)
            if let grid = LumaGrid.sample(of: buffer, step: maskThresholds.gridStep) {
                builder.add(luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height)
            }
            self.builder = builder
            if builder.isComplete, let mask = builder.result() {
                self.builder = nil
                // Tracking starts afresh from the next frame, inside the settled region.
                clearTracking()
                fieldState = mask.isTrusted ? .ready(mask) : .untrusted(mask)
                maskImage = mask.tintImage()
                isAwaitingReview = requiresReview
            } else {
                fieldState = .learning(progress: builder.progress)
            }
            return true
        }

        /// Points both registrations at the region the mode and the mask call for.
        private func applyRegion(frameSize: CGSize) {
            switch fieldMode {
            case .wholeFrame:
                registrationRect = nil
            case .centreSquare:
                registrationRect = EyepieceField.centreSquare(frameSize: frameSize)
            case .auto, .brightRegion:
                switch fieldState {
                case .learning: registrationRect = nil
                case .ready(let mask): registrationRect = mask.registrationRect
                case .untrusted: registrationRect = EyepieceField.centreSquare(frameSize: frameSize)
                }
            }
            let region = registrationRect.map {
                EyepieceField.visionRegion(of: $0, frameSize: frameSize)
            }
            shake.regionOfInterest = region
            travel.regionOfInterest = region
        }

        // MARK: Hops

        private func anchorOn(_ buffer: CVPixelBuffer) {
            travel.hold(buffer)
            anchor = buffer
        }

        /// How well the two frames agree once the picture is moved by the hop.
        ///
        /// `offset` is the registered shift from `anchor` to `current`, which is what
        /// `PanoramaStitcher.contentShift` computes the same way (a request targeted at the
        /// earlier frame, run on the later one, vertical flipped). That function then asks
        /// for `agreement(movedBy: -shift)`, so this passes the NEGATED offset to match it.
        private func agreement(
            from anchor: CVPixelBuffer, to current: CVPixelBuffer, offset: CGPoint
        ) -> Double? {
            guard let first = image(of: anchor), let second = image(of: current) else { return nil }
            return PanoramaStitcher.agreement(
                between: first, and: second, movedBy: CGPoint(x: -offset.x, y: -offset.y))
        }

        private func image(of buffer: CVPixelBuffer) -> CGImage? {
            let image = CIImage(cvPixelBuffer: buffer)
            return context.createCGImage(image, from: image.extent)
        }
    }
#endif
