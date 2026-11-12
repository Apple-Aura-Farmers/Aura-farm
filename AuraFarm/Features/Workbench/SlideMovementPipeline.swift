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
        private var blankMatch = PictureMatchCheck()
        private(set) var blankReturnsMatched = 0
        private(set) var blankReturnsUnmatched = 0

        // The picture check: a stored copy of the box at Mark start (an image of its own, never
        // a camera buffer) and the position then.
        private var startRequested = false
        private var startPicture: CGImage?
        private var startBox: CGRect?
        private var startPosition = CGPoint.zero
        private var startCheck = PictureMatchCheck()
        private var startAccepted: CGPoint?
        private var startMisses = 0
        /// Frames in a row a confirmed start match was refused before it is checked afresh.
        private let startMissesToRecheck = 3
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

            var outcome = TrackOutcome()
            var start = StartReading()
            if !learning {
                outcome = track(
                    buffer, seconds: seconds, frameSize: frameSize, referenceSide: referenceSide,
                    boxStats: boxStats, measureAgreement: measureAgreement)
                start = updateStartPicture(
                    buffer, frameShift: outcome.frameShift, boxSide: boxSide, frameSize: frameSize)
            }

            let taken = ContinuousClock.now - started
            let milliseconds =
                Double(taken.components.seconds) * 1000
                + Double(taken.components.attoseconds) / 1e15
            let fps = rate.record(seconds)
            return SlideMovementStep(
                stats: stats,
                shake: learning ? nil : outcome.frameShift,
                anchorOffset: outcome.offset,
                position: odometer.position,
                positionFrames: odometer.positionInFrames(shortSide: shortSide),
                positionFields: odometer.positionInFields(fieldSide: boxSide),
                boxSide: boxSide, hopLimit: hopLimit, thumbnail: thumbnail,
                hops: odometer.hops,
                gaps: odometer.gaps,
                isLost: odometer.isLost,
                event: outcome.event,
                hopAgreement: outcome.agreement,
                frameSize: frameSize,
                fieldState: fieldMode.learnsMask ? fieldState : nil,
                registrationRect: registrationRect,
                fieldMode: fieldMode,
                analysisMilliseconds: milliseconds,
                analyzedFps: fps, awaitingReview: isAwaitingReview, boxStats: boxStats,
                usedOffset: outcome.usedOffset, reading: outcome.reading,
                predictedStreak: outcome.streak, hasDetail: detail.hasDetail,
                blindStretches: blindStretches, blankReturnsMatched: blankReturnsMatched,
                blankReturnsUnmatched: blankReturnsUnmatched,
                blankReturnEvent: outcome.blankReturnEvent, startMatch: start.match,
                trueOffStartFields: start.trueOffFields, trackerErrorFields: start.errorFields,
                pictureCheck: start.state)
        }

        // MARK: Tracking

        private struct TrackOutcome {
            var offset: CGPoint?
            var usedOffset: CGPoint?
            var frameShift: CGPoint?
            var reading = "missing"
            var streak = 0
            var event = HopOdometer.Event.none
            var agreement: Double?
            var blankReturnEvent = ""
        }

        private struct StartReading {
            var match: CGPoint?
            var trueOffFields: Double?
            var errorFields: Double?
            var state = "none"
        }

        /// One tracked frame: the frame-to-frame shift, the detail check, and the reading
        /// against the anchor (or, after a stretch with nothing to track, the match of the
        /// held picture).
        private func track(
            _ buffer: CVPixelBuffer, seconds: Double, frameSize: CGSize, referenceSide: Double?,
            boxStats: FrameStats, measureAgreement: Bool
        ) -> TrackOutcome {
            var outcome = TrackOutcome()
            outcome.frameShift = measureFrameShift(buffer)
            let hadDetail = detail.hasDetail
            detail.update(boxSharpness: boxStats.sharpness)
            if hadDetail && !detail.hasDetail {
                blindStretches += 1
                resumeAfterBlind = true
                // Lost again while matching: abandon the check; the held anchor stays.
                blankMatch.reset()
            }
            guard let held = anchor else {
                // No anchor yet: anchor on this frame. Not a lost reading.
                anchorOn(buffer)
                return outcome
            }
            // Nothing to follow: paused. Not a lost reading, no distance added, and the held
            // anchor is kept exactly as it is.
            guard detail.hasDetail else { return outcome }

            let boxSide = referenceSide ?? Double(min(frameSize.width, frameSize.height))
            if resumeAfterBlind {
                let measured = measureAnchorOffset(held: held, current: buffer)
                outcome.offset = measured
                switch blankMatch.feed(
                    offset: measured, frameShift: outcome.frameShift, boxSide: boxSide)
                {
                case .pending:
                    outcome.reading = "matching"
                    return outcome
                case .confirmed(let confirmed):
                    // The held picture is found again: the position is recovered with no loss.
                    resumeAfterBlind = false
                    blankMatch.reset()
                    blankReturnsMatched += 1
                    outcome.blankReturnEvent = "matched"
                    consistency.reset(to: confirmed)
                    outcome.offset = confirmed
                    outcome.usedOffset = confirmed
                    outcome.reading = "measured"
                    advance(
                        &outcome, held: held, buffer: buffer, seconds: seconds, frameSize: frameSize,
                        referenceSide: referenceSide, committing: nil, measureAgreement: measureAgreement)
                    return outcome
                case .rejected:
                    // Not found: carry on from the last known position, which may be off.
                    resumeAfterBlind = false
                    blankMatch.reset()
                    blankReturnsUnmatched += 1
                    outcome.blankReturnEvent = "unmatched"
                    odometer.rebase()
                    anchorOn(buffer)
                    return outcome
                }
            }

            readingIndex += 1
            var measured = measureAnchorOffset(held: held, current: buffer)
            if let override = anchorReadingOverride { measured = override(readingIndex, measured) }
            outcome.offset = measured
            var verdict = ReadingVerdict.missing
            if let box = registrationRect {
                verdict = consistency.judge(
                    anchorOffset: measured, frameShift: outcome.frameShift,
                    boxSide: Double(min(box.width, box.height)))
            } else if let measured {
                verdict = .measured(measured)
            }
            outcome.reading = verdict.csvName
            outcome.streak = consistency.predictedStreak
            outcome.usedOffset = verdict.offset
            var committing: CGPoint?
            if case .predicted(let predicted) = verdict, consistency.mustCommit {
                // Predictions have stood in for too long: trust them as a hop.
                committing = predicted
            }
            advance(
                &outcome, held: held, buffer: buffer, seconds: seconds, frameSize: frameSize,
                referenceSide: referenceSide, committing: committing,
                measureAgreement: measureAgreement)
            return outcome
        }

        /// Hands the odometer the offset to use, and re-anchors when it says so.
        private func advance(
            _ outcome: inout TrackOutcome, held: CVPixelBuffer, buffer: CVPixelBuffer, seconds: Double,
            frameSize: CGSize, referenceSide: Double?, committing: CGPoint?, measureAgreement: Bool
        ) {
            var result: (event: HopOdometer.Event, reanchor: Bool)
            if let committing {
                odometer.commit(offset: committing)
                result = (.hop, true)
            } else {
                result = odometer.update(
                    offset: outcome.usedOffset, frameSize: frameSize, referenceSide: referenceSide)
            }
            outcome.event = result.event
            if outcome.event == .hop, measureAgreement, let used = outcome.usedOffset,
                seconds - lastAgreementAt >= Self.agreementEverySeconds
            {
                lastAgreementAt = seconds
                outcome.agreement = agreement(from: held, to: buffer, offset: used)
            }
            if result.reanchor { anchorOn(buffer) }
        }

        // MARK: Picture check

        /// Remembers the box as it is at the next tracked frame, with the position then, so
        /// the true distance from here can be measured later by matching the picture. The copy
        /// is an image of its own; the camera's buffer is never kept for this.
        func setStartPicture() {
            startRequested = true
        }

        func clearStartPicture() {
            startRequested = false
            startPicture = nil
            startBox = nil
            startAccepted = nil
            startMisses = 0
            startCheck.reset()
        }

        private func updateStartPicture(
            _ buffer: CVPixelBuffer, frameShift: CGPoint?, boxSide: Double, frameSize: CGSize
        ) -> StartReading {
            let rect = registrationRect ?? CGRect(origin: .zero, size: frameSize)
            if startRequested {
                startRequested = false
                if let copy = boxRegistration.copy(of: buffer, box: rect, context: context) {
                    startPicture = copy
                    startBox = rect
                    startPosition = odometer.position
                    startAccepted = nil
                    startMisses = 0
                    startCheck.reset()
                }
            }
            guard let picture = startPicture else { return StartReading() }
            // The box moved (re-detected, adjusted, mode changed): the stored picture is no
            // longer the same patch of the view.
            guard rect == startBox else {
                clearStartPicture()
                return StartReading()
            }

            let moved = CGPoint(
                x: odometer.position.x - startPosition.x, y: odometer.position.y - startPosition.y)
            let limit = startCheck.thresholds.maxOffsetOfBox * boxSide
            guard detail.hasDetail, hypot(Double(moved.x), Double(moved.y)) <= limit else {
                startCheck.reset()
                startAccepted = nil
                return StartReading(state: detail.hasDetail ? "out_of_range" : "matching")
            }

            let measured = boxRegistration.offset(fromStored: picture, to: buffer, box: rect)
            if let accepted = startAccepted {
                // Confirmed: keep measuring, but accept only what agrees with the last
                // accepted reading plus the frame-to-frame movement.
                let expected = CGPoint(
                    x: accepted.x + (frameShift?.x ?? 0), y: accepted.y + (frameShift?.y ?? 0))
                if let measured,
                    hypot(Double(measured.x - expected.x), Double(measured.y - expected.y))
                        <= startCheck.thresholds.maxStepDisagreementOfBox * boxSide
                {
                    startAccepted = measured
                    startMisses = 0
                } else {
                    startMisses += 1
                    if startMisses >= startMissesToRecheck {
                        startAccepted = nil
                        startMisses = 0
                        startCheck.reset()
                        return StartReading(state: "matching")
                    }
                    startAccepted = expected
                }
            } else {
                if case .confirmed(let offset) = startCheck.feed(
                    offset: measured, frameShift: frameShift, boxSide: boxSide)
                {
                    startAccepted = offset
                } else {
                    return StartReading(state: "matching")
                }
            }

            guard let match = startAccepted, boxSide > 0 else { return StartReading(state: "matching") }
            return StartReading(
                match: match, trueOffFields: hypot(Double(match.x), Double(match.y)) / boxSide,
                errorFields: hypot(Double(moved.x - match.x), Double(moved.y - match.y)) / boxSide,
                state: "confirmed")
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
            blankMatch.reset()
            blankReturnsMatched = 0
            blankReturnsUnmatched = 0
            clearStartPicture()
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
