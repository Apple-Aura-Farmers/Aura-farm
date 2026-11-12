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
        /// The position in frames (the frame's short side), kept for the CSV.
        var positionFrames: CGPoint
        /// The position in fields: one field is `boxSide`, the useful part of the view.
        var positionFields: CGPoint
        /// The side of the registration box in px; the frame's short side with no box.
        var boxSide: Double
        /// The hop distance in use, px.
        var hopLimit: Double
        /// A fresh "What the app sees" picture, at most once a second and only when asked for.
        var thumbnail: CGImage?
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
        /// How long this frame's analysis took, in milliseconds.
        var analysisMilliseconds: Double
        /// Analyzed frames per second over the last second.
        var analyzedFps: Double
        /// Whether the learned field is waiting for the person to confirm or adjust it.
        var awaitingReview = false
        /// Brightness, sharpness and contrast inside the registration box (the whole frame's
        /// when there is no box). `stats` stays the whole frame's, for comparison.
        var boxStats: FrameStats
        /// The offset from the anchor the odometer was given: measured, or predicted when the
        /// measurement disagreed with the frame-to-frame movement. `anchorOffset` stays what
        /// registration returned.
        var usedOffset: CGPoint?
        /// "measured", "predicted" or "missing"; see `ReadingVerdict`.
        var reading = "missing"
        var predictedStreak = 0
        /// False while the box holds too little detail to follow.
        var hasDetail = true
        var blindStretches = 0

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
        private let boxRegistration = BoxRegistration()
        /// The previous frame, held only while a box is in use (`shake` holds it otherwise).
        private var previousFrame: CVPixelBuffer?
        private var consistency = ReadingConsistency()
        private var detail = DetailCheck()
        private(set) var blindStretches = 0
        /// Set when detail went; the first frame with detail again re-anchors.
        private var resumeAfterBlind = false
        private var readingIndex = 0
        /// A seam for tests: replaces the anchor registration's answer. Called with the
        /// reading's number (1 for the first since tracking began) and what Vision returned.
        var anchorReadingOverride: ((_ index: Int, _ measured: CGPoint?) -> CGPoint?)?
        private var odometer: HopOdometer
        /// The frame the travel is measured from. The same buffer `travel` holds, kept here
        /// as well because a hop's agreement needs both frames as images.
        private var anchor: CVPixelBuffer?
        private lazy var context = CIContext(options: [.useSoftwareRenderer: false])
        private var lastAgreementAt = -Double.infinity
        private var rate = FrameRateMeter()
        private var builder: FieldMaskBuilder?
        private var lastFrameSize = CGSize.zero

        /// Whether to make the "What the app sees" picture, at most once a second.
        var makesThumbnail = false {
            didSet { if makesThumbnail { lastThumbnailAt = -.infinity } }
        }
        private var lastThumbnailAt = -Double.infinity
        /// The last luma grid sampled for the picture: a small copy, never a pixel buffer.
        private var lastLuma: (luma: [UInt8], width: Int, height: Int)?

        /// When true, tracking waits after the mask is learned until `confirmField()`, so the
        /// person can check it (and adjust it with `adjustField`) first. The live lab sets it.
        var requiresReview = false
        private(set) var isAwaitingReview = false
        /// Where registration looks once the mode and the mask are settled, in frame pixels.
        private var registrationRect: CGRect?

        init(
            thresholds: HopOdometerThresholds = HopOdometerThresholds(),
            maskThresholds: FieldMaskThresholds = FieldMaskThresholds(),
            consistencyThresholds: ReadingConsistencyThresholds = ReadingConsistencyThresholds(),
            detailThresholds: DetailThresholds = DetailThresholds()
        ) {
            odometer = HopOdometer(thresholds: thresholds)
            self.maskThresholds = maskThresholds
            consistency = ReadingConsistency(thresholds: consistencyThresholds)
            detail = DetailCheck(thresholds: detailThresholds)
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
            // The box the movement is measured in sizes the hop limits and the distance unit.
            let referenceSide = registrationRect.map { Double(min($0.width, $0.height)) }
            let shortSide = Double(min(frameSize.width, frameSize.height))
            let boxSide = referenceSide ?? shortSide
            let hopLimit = odometer.hopDistance(frameSize: frameSize, referenceSide: referenceSide)
            var thumbnail: CGImage?
            if makesThumbnail, seconds - lastThumbnailAt >= 1 {
                lastThumbnailAt = seconds
                thumbnail = makeThumbnail(from: buffer)
            }

            let boxStats =
                registrationRect.flatMap {
                    FrameAnalyzer.stats(of: buffer, in: $0, step: Self.sampleStep)
                } ?? stats

            var offset: CGPoint?
            var usedOffset: CGPoint?
            var frameShift: CGPoint?
            var verdictName = "missing"
            var streak = 0
            var event = HopOdometer.Event.none
            var agreement: Double?

            if !learning {
                frameShift = measureFrameShift(buffer)
                let hadDetail = detail.hasDetail
                detail.update(boxSharpness: boxStats.sharpness)
                if hadDetail && !detail.hasDetail {
                    blindStretches += 1
                    resumeAfterBlind = true
                }

                if let held = anchor {
                    if !detail.hasDetail {
                        // Nothing to follow: paused. Not a lost reading, no distance added.
                    } else if resumeAfterBlind {
                        // Detail is back: carry on from the last known position.
                        resumeAfterBlind = false
                        odometer.rebase()
                        anchorOn(buffer)
                    } else {
                        readingIndex += 1
                        var measured = measureAnchorOffset(held: held, current: buffer)
                        if let override = anchorReadingOverride {
                            measured = override(readingIndex, measured)
                        }
                        offset = measured
                        var verdict = ReadingVerdict.missing
                        if let box = registrationRect {
                            verdict = consistency.judge(
                                anchorOffset: measured, frameShift: frameShift,
                                boxSide: Double(min(box.width, box.height)))
                        } else if let measured {
                            verdict = .measured(measured)
                        }
                        verdictName = verdict.csvName
                        streak = consistency.predictedStreak
                        usedOffset = verdict.offset

                        var result: (event: HopOdometer.Event, reanchor: Bool)
                        if case .predicted(let predicted) = verdict, consistency.mustCommit {
                            // Predictions have stood in for too long: trust them as a hop.
                            odometer.commit(offset: predicted)
                            result = (.hop, true)
                        } else {
                            result = odometer.update(
                                offset: usedOffset, frameSize: frameSize,
                                referenceSide: referenceSide)
                        }
                        event = result.event
                        if event == .hop, measureAgreement, let usedOffset,
                            seconds - lastAgreementAt >= Self.agreementEverySeconds
                        {
                            lastAgreementAt = seconds
                            agreement = self.agreement(from: held, to: buffer, offset: usedOffset)
                        }
                        if result.reanchor { anchorOn(buffer) }
                    }
                } else {
                    // No anchor yet: anchor on this frame. Not a lost reading.
                    anchorOn(buffer)
                }
            }

            let taken = ContinuousClock.now - started
            let milliseconds =
                Double(taken.components.seconds) * 1000
                + Double(taken.components.attoseconds) / 1e15
            let fps = rate.record(seconds)
            return SlideMovementStep(
                stats: stats,
                shake: learning ? nil : frameShift,
                anchorOffset: offset,
                position: odometer.position,
                positionFrames: odometer.positionInFrames(shortSide: shortSide),
                positionFields: odometer.positionInFields(fieldSide: boxSide),
                boxSide: boxSide, hopLimit: hopLimit, thumbnail: thumbnail,
                hops: odometer.hops,
                gaps: odometer.gaps,
                isLost: odometer.isLost,
                event: event,
                hopAgreement: agreement,
                frameSize: frameSize,
                fieldState: fieldMode.learnsMask ? fieldState : nil,
                registrationRect: registrationRect,
                fieldMode: fieldMode,
                analysisMilliseconds: milliseconds,
                analyzedFps: fps, awaitingReview: isAwaitingReview, boxStats: boxStats,
                usedOffset: usedOffset, reading: verdictName, predictedStreak: streak,
                hasDetail: detail.hasDetail, blindStretches: blindStretches)
        }

        // MARK: Field mask

        /// Samples the luma grid the same way learning does and draws the mask and box on it.
        private func makeThumbnail(from buffer: CVPixelBuffer) -> CGImage? {
            guard let grid = LumaGrid.sample(of: buffer, step: maskThresholds.gridStep) else {
                return nil
            }
            lastLuma = grid
            var mask: FieldMask?
            switch fieldState {
            case .ready(let learned), .untrusted(let learned): mask = learned
            case .learning: break
            }
            return FieldMaskPicture.image(
                luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                mask: fieldMode.learnsMask ? mask : nil, registrationRect: registrationRect,
                gridStep: maskThresholds.gridStep)
        }

        private func clearTracking() {
            odometer.reset()
            travel.reset()
            shake.reset()
            anchor = nil
            previousFrame = nil
            consistency.reset()
            detail.reset()
            blindStretches = 0
            resumeAfterBlind = false
            readingIndex = 0
        }

        private func restartLearning() {
            builder = nil
            isAwaitingReview = false
            fieldState = .learning(progress: 0)
            registrationRect = nil
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
                isAwaitingReview = requiresReview
            } else {
                fieldState = .learning(progress: builder.progress)
            }
            return true
        }

        /// Works out the region the mode and the mask call for.
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
            // A box is registered by cropping both frames (`BoxRegistration`); the old
            // regions stay unset so the whole-frame path really is the whole frame.
            shake.regionOfInterest = nil
            travel.regionOfInterest = nil
        }

        // MARK: Hops

        private func anchorOn(_ buffer: CVPixelBuffer) {
            travel.hold(buffer)
            anchor = buffer
            consistency.reset()
        }

        /// The frame-to-frame shift. With a box, both frames are cropped to it; with the whole
        /// frame it is `ShakeEstimator`'s, as it always was.
        private func measureFrameShift(_ buffer: CVPixelBuffer) -> CGPoint? {
            defer { previousFrame = registrationRect == nil ? nil : buffer }
            guard let box = registrationRect else {
                _ = shake.update(with: buffer)
                return shake.lastShift
            }
            shake.reset()
            guard let previousFrame else { return nil }
            return boxRegistration.offset(from: previousFrame, to: buffer, box: box)
        }

        private func measureAnchorOffset(held: CVPixelBuffer, current: CVPixelBuffer) -> CGPoint? {
            guard let box = registrationRect else { return travel.offset(to: current) }
            return boxRegistration.offset(from: held, to: current, box: box)
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
