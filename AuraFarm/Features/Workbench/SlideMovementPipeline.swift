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
        /// Detail returns that were recovered by matching the held picture, and those that
        /// could not be, so the position may be off since then.
        var blankReturnsMatched = 0
        var blankReturnsUnmatched = 0
        /// "matched" or "unmatched" on the frame where a return was decided, else "".
        var blankReturnEvent = ""
        /// The picture check against the Mark start picture: where the start picture sits
        /// against this frame (px, held to current), which equals the true change of position
        /// since Mark start. nil when not available.
        var startMatch: CGPoint?
        var trueOffStartFields: Double?
        /// How far the tracker's position change since Mark start is from `startMatch`, in
        /// fields.
        var trackerErrorFields: Double?
        /// "none", "out_of_range", "matching" or "confirmed".
        var pictureCheck = "none"
        /// The tracker's whole reading for this frame; the guide reads its conveniences.
        var tracking: SlideTrackerReading

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

    /// The measurement chain of the slide movement lab: stats, field region, tracking. A thin
    /// wrapper over `FieldRegionLearner` and `SlideTracker`, which hold the logic the capture
    /// screen shares. One instance per run; every call must come from the same serial queue
    /// (the analysis queue live, the reader's queue for a video).
    ///
    /// In Auto mode the first frames of a run only learn the eyepiece mask: no hops, no lost.
    final class SlideMovementPipeline {
        /// The lab samples every 4th pixel for its statistics: coarser than the capture
        /// screen's 2, to keep a Debug build up with the camera. Sharpness read this way is NOT
        /// on the capture screen's scale. Box stats use the tracker's step, the same number.
        static let sampleStep = SlideTracker.statsStep

        private let learner: FieldRegionLearner
        private let tracker: SlideTracker
        private let maskThresholds: FieldMaskThresholds
        private var rate = FrameRateMeter()

        /// Where registration looks. Set from the analysis queue. Choosing Auto starts
        /// learning the mask.
        var fieldMode: FieldRegionMode {
            get { learner.mode }
            set { learner.mode = newValue }
        }

        /// Where the mask has got to.
        var fieldState: FieldState { learner.state }

        /// A seam for tests: replaces the anchor registration's answer.
        var anchorReadingOverride: ((_ index: Int, _ measured: CGPoint?) -> CGPoint?)? {
            get { tracker.anchorReadingOverride }
            set { tracker.anchorReadingOverride = newValue }
        }

        /// Whether to make the "What the app sees" picture, at most once a second.
        var makesThumbnail = false {
            didSet { if makesThumbnail { lastThumbnailAt = -.infinity } }
        }
        private var lastThumbnailAt = -Double.infinity

        /// When true, tracking waits after the mask is learned until `confirmField()`, so the
        /// person can check it (and adjust it with `adjustField`) first. The live lab sets it.
        var requiresReview: Bool {
            get { learner.requiresReview }
            set { learner.requiresReview = newValue }
        }
        var isAwaitingReview: Bool { learner.isAwaitingReview }

        init(
            thresholds: HopOdometerThresholds = HopOdometerThresholds(),
            maskThresholds: FieldMaskThresholds = FieldMaskThresholds(),
            consistencyThresholds: ReadingConsistencyThresholds = ReadingConsistencyThresholds(),
            detailThresholds: DetailThresholds = DetailThresholds()
        ) {
            self.maskThresholds = maskThresholds
            learner = FieldRegionLearner(maskThresholds: maskThresholds)
            tracker = SlideTracker(
                odometer: thresholds, consistency: consistencyThresholds, detail: detailThresholds)
        }

        /// Whether the eyepiece mask is still being learned.
        var isLearning: Bool { learner.isLearning }

        /// Detail returns recovered by matching the held picture, and those that were not.
        var blankReturnsMatched: Int { tracker.blankReturnsMatched }
        var blankReturnsUnmatched: Int { tracker.blankReturnsUnmatched }

        /// Forgets the position and the anchor: the next frame anchors afresh. A mask that is
        /// still being learned starts again; one already learned is kept.
        func resetPosition() {
            tracker.reset()
            learner.restartIfLearning()
        }

        /// The person is happy with the field: tracking starts afresh from the next frame.
        func confirmField() { learner.confirm() }

        /// Replaces the learned field with a circle the person drew.
        func adjustField(to circle: FieldCircle) { learner.adjust(to: circle) }

        /// Forgets the learned mask and learns it again.
        func redetectField() { learner.redetect() }

        /// Remembers the box at the next tracked frame for the picture check.
        func setStartPicture() { tracker.setReferencePicture() }

        func clearStartPicture() { tracker.clearReferencePicture() }

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
            let update = learner.process(buffer, frameSize: frameSize)
            if update.regionChanged { tracker.reset() }
            tracker.measuresHopAgreement = measureAgreement
            let box = learner.registrationRect
            let reading =
                update.spentLearning
                ? tracker.idle(buffer, box: box, frameSize: frameSize, wholeFrameStats: stats)
                : tracker.track(
                    buffer, box: box, frameSize: frameSize, seconds: seconds, wholeFrameStats: stats)
            var thumbnail: CGImage?
            if makesThumbnail, seconds - lastThumbnailAt >= 1 {
                lastThumbnailAt = seconds
                thumbnail = makeThumbnail(from: buffer)
            }

            let taken = ContinuousClock.now - started
            let milliseconds =
                Double(taken.components.seconds) * 1000
                + Double(taken.components.attoseconds) / 1e15
            let shortSide = Double(min(frameSize.width, frameSize.height))
            return SlideMovementStep(
                stats: stats,
                shake: reading.frameShift,
                anchorOffset: reading.anchorOffset,
                position: reading.position,
                positionFrames: shortSide > 0
                    ? CGPoint(x: reading.position.x / shortSide, y: reading.position.y / shortSide)
                    : .zero,
                positionFields: reading.positionFields,
                boxSide: reading.boxSide, hopLimit: reading.hopLimit, thumbnail: thumbnail,
                hops: reading.hops,
                gaps: reading.gaps,
                isLost: reading.isLost,
                event: reading.event,
                hopAgreement: reading.hopAgreement,
                frameSize: frameSize,
                fieldState: fieldMode.learnsMask ? fieldState : nil,
                registrationRect: box,
                fieldMode: fieldMode,
                analysisMilliseconds: milliseconds,
                analyzedFps: rate.record(seconds), awaitingReview: isAwaitingReview,
                boxStats: reading.boxStats,
                usedOffset: reading.usedOffset, reading: reading.reading,
                predictedStreak: reading.predictedStreak, hasDetail: reading.hasDetail,
                blindStretches: reading.blindStretches,
                blankReturnsMatched: reading.blankReturnsMatched,
                blankReturnsUnmatched: reading.blankReturnsUnmatched,
                blankReturnEvent: reading.blankReturnEvent, startMatch: reading.referenceMatch,
                trueOffStartFields: reading.trueOffReferenceFields,
                trackerErrorFields: reading.trackerErrorFields,
                pictureCheck: reading.pictureCheck, tracking: reading)
        }

        /// Samples the luma grid the same way learning does and draws the mask and box on it.
        private func makeThumbnail(from buffer: CVPixelBuffer) -> CGImage? {
            guard let grid = LumaGrid.sample(of: buffer, step: maskThresholds.gridStep) else {
                return nil
            }
            return FieldMaskPicture.image(
                luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                mask: fieldMode.learnsMask ? fieldState.mask : nil,
                registrationRect: learner.registrationRect, gridStep: maskThresholds.gridStep)
        }
    }
#endif
