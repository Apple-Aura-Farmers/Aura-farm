import CoreImage
import CoreVideo
import Foundation

/// The measurement chain that follows a slide moved by hand: frame-to-frame shift, the detail
/// check, readings against an anchor with false-jump rejection, the hop odometer, recovery
/// after blank glass, and the picture check against a reference picture.
///
/// One instance per run; every call must come from the same serial queue. Holds at most the
/// anchor and the previous frame as camera buffers, plus the reference picture as a
/// `CGImage` of its own, never a camera buffer.
final class SlideTracker {
    /// The step the box statistics are sampled at. `DetailThresholds.minBoxSharpness` and the
    /// `ViewClassifier` thresholds were measured at this step, so box stats are ALWAYS taken
    /// at it. The capture screen's own quality stats use step 2 and are on a different scale.
    static let statsStep = 4
    /// The least gap between two agreement measurements, in seconds. Measuring converts two
    /// frames to images and correlates them, far dearer than the rest of the chain.
    static let agreementEverySeconds = 1.0

    /// Whether a hop may be checked against `PanoramaStitcher`, at most once a second.
    var measuresHopAgreement = false
    /// A seam for tests: replaces the anchor registration's answer. Called with the reading's
    /// number (1 for the first since tracking began) and what Vision returned.
    var anchorReadingOverride: ((_ index: Int, _ measured: CGPoint?) -> CGPoint?)?
    /// A seam for tests: replaces the reference picture's registration, called with the
    /// number of readings taken since the picture was kept and what Vision returned.
    var referenceReadingOverride: ((_ index: Int, _ measured: CGPoint?) -> CGPoint?)?
    /// A seam for tests: replaces the frame-to-frame shift. Called with the number of frames
    /// tracked so far (1 for the first) and what the registration returned.
    var frameShiftOverride: ((_ index: Int, _ measured: CGPoint?) -> CGPoint?)?

    private let shake = ShakeEstimator()
    private let travel = TravelSinceLastFrame()
    private let boxRegistration = BoxRegistration()
    /// The previous frame, held only while a box is in use (`shake` holds it otherwise).
    private var previousFrame: CVPixelBuffer?
    private var consistency: ReadingConsistency
    private var detail: DetailCheck
    private var odometer: HopOdometer
    private(set) var blindStretches = 0
    /// Set when detail went; the first frame with detail again re-anchors.
    private var resumeAfterBlind = false
    private var readingIndex = 0
    private var blankMatch: PictureMatchCheck
    private(set) var blankReturnsMatched = 0
    private(set) var blankReturnsUnmatched = 0
    /// Frames dropped because their frame-to-frame shift was too large to be real (a running
    /// count), and how many times `maxInARow` of them in a row gave up and let the frame through.
    private(set) var ghostFrames = 0
    private(set) var ghostFallbacks = 0
    private var ghostRun = 0
    /// Frames skipped for being near empty (a running count), and how many in a row.
    private(set) var sparseSkips = 0
    private var sparseRun = 0
    private var ghostThresholds: GhostFrameThresholds
    private var frameIndex = 0
    /// The last frame-to-frame shift of a frame that was not a ghost, which a ghost frame carries.
    private var lastGoodShake: CGPoint?
    /// The frame the travel is measured from. The same buffer `travel` holds, kept here as
    /// well because a hop's agreement needs both frames as images.
    private var anchor: CVPixelBuffer?
    private lazy var context = CIContext(options: [.useSoftwareRenderer: false])
    private var lastAgreementAt = -Double.infinity
    /// How long the last feature-cell count took, in milliseconds.
    private(set) var featureMilliseconds = 0.0
    /// How long the last four-quarter measurement took, in milliseconds.
    private(set) var quarterMilliseconds = 0.0
    /// Whether a box with little variance but distinct features still counts as having detail.
    var tracksSparse: Bool {
        get { detail.thresholds.tracksSparse }
        set { detail.thresholds.tracksSparse = newValue }
    }
    /// The box of the frame being tracked, in frame pixels; nil for the whole frame.
    private var box: CGRect?

    // The reference picture: a stored copy of the box (an image of its own) and the position
    // then.
    private var referenceRequested = false
    private var referencePicture: CGImage?
    private var referenceBox: CGRect?
    private var referencePosition = CGPoint.zero
    private var referenceCheck: PictureMatchCheck
    private var referenceAccepted: CGPoint?
    private var referenceMisses = 0
    private var referenceReadings = 0
    /// Frames in a row a confirmed reference match was refused before it is checked afresh.
    private let referenceMissesToRecheck = 3

    init(
        odometer: HopOdometerThresholds = HopOdometerThresholds(),
        consistency: ReadingConsistencyThresholds = ReadingConsistencyThresholds(),
        detail: DetailThresholds = DetailThresholds(),
        pictureMatch: PictureMatchThresholds = PictureMatchThresholds(),
        ghost: GhostFrameThresholds = GhostFrameThresholds()
    ) {
        ghostThresholds = ghost
        self.odometer = HopOdometer(thresholds: odometer)
        self.consistency = ReadingConsistency(thresholds: consistency)
        self.detail = DetailCheck(thresholds: detail)
        blankMatch = PictureMatchCheck(thresholds: pictureMatch)
        referenceCheck = PictureMatchCheck(thresholds: pictureMatch)
    }

    /// Forgets the position, the anchor and the reference picture: the next frame anchors afresh.
    func reset() {
        odometer.reset()
        travel.reset()
        shake.reset()
        anchor = nil
        previousFrame = nil
        consistency.reset()
        detail.reset()
        blindStretches = 0
        resumeAfterBlind = false
        ghostRun = 0
        lastGoodShake = nil
        readingIndex = 0
        blankMatch.reset()
        blankReturnsMatched = 0
        blankReturnsUnmatched = 0
        clearReferencePicture()
    }

    /// Remembers the box as it is at the next tracked frame, with the position then, so the
    /// true distance from here can be measured later by matching the picture.
    func setReferencePicture() {
        referenceRequested = true
    }

    func clearReferencePicture() {
        referenceRequested = false
        referencePicture = nil
        referenceBox = nil
        referenceAccepted = nil
        referenceMisses = 0
        referenceReadings = 0
        referenceCheck.reset()
    }

    /// The tracker's numbers as they stand, for a frame that is not tracked (the field is
    /// still being learned or reviewed). Nothing is measured.
    func idle(
        _ buffer: CVPixelBuffer, box: CGRect?, frameSize: CGSize, wholeFrameStats: FrameStats? = nil
    ) -> SlideTrackerReading {
        self.box = box
        return reading(
            Outcome(), boxStats: boxStats(buffer, wholeFrameStats), frameSize: frameSize,
            start: ReferenceReading())
    }

    /// Tracks one frame inside `box` (frame pixels, top-left origin; nil for the whole frame).
    /// - Parameters:
    ///   - seconds: the frame's time, to ration the agreement measurement.
    ///   - wholeFrameStats: the whole frame's stats at `statsStep` when the caller already has
    ///     them, to save measuring again when there is no box.
    func track(
        _ buffer: CVPixelBuffer, box: CGRect?, frameSize: CGSize, seconds: Double,
        wholeFrameStats: FrameStats? = nil
    ) -> SlideTrackerReading {
        self.box = box
        let stats = boxStats(buffer, wholeFrameStats)
        let halfSharpness = box.map { measureHalves(of: $0, in: buffer, fallback: stats.sharpness) }
        // The anchor the offset below is measured against, before this frame may replace it.
        let heldAnchor = anchor
        var features: FeatureCells?
        if let box {
            let started = ContinuousClock.now
            features = FrameAnalyzer.featureCells(
                of: buffer, in: box, featureContrast: detail.thresholds.featureContrast)
            let taken = ContinuousClock.now - started
            featureMilliseconds =
                Double(taken.components.seconds) * 1000 + Double(taken.components.attoseconds) / 1e15
        }
        let outcome = trackFrame(
            buffer, seconds: seconds, frameSize: frameSize, boxStats: stats, features: features)
        let boxSide = Self.side(of: box, frameSize: frameSize)
        let start = updateReference(
            buffer, frameShift: outcome.frameShift, boxSide: boxSide, frameSize: frameSize)
        var result = reading(outcome, boxStats: stats, frameSize: frameSize, start: start)
        result.halfSharpness = halfSharpness
        result.featureCells = features?.cells ?? 0
        result.ghostFrames = ghostFrames
        result.ghostFallbacks = ghostFallbacks
        result.sparseSkips = sparseSkips
        result.featureQuarters = features?.quarters ?? 0
        result.sparse = detail.hasDetail && detail.isSparse
        if let box, let heldAnchor, let halfSharpness, detail.hasDetail {
            let offset = outcome.usedOffset ?? outcome.offset ?? odometer.live
            result.halfFocusRatio = focusRatios(
                of: box, current: halfSharpness, anchor: heldAnchor, offset: offset)
        }
        return result
    }

    /// The four halves of the box in whole pixels: left, right, top, bottom.
    private func halfRects(of box: CGRect) -> [CGRect] {
        let halfWidth = (box.width / 2).rounded(.down)
        let halfHeight = (box.height / 2).rounded(.down)
        return [
            CGRect(x: box.minX, y: box.minY, width: halfWidth, height: box.height),
            CGRect(x: box.minX + halfWidth, y: box.minY, width: box.width - halfWidth, height: box.height),
            CGRect(x: box.minX, y: box.minY, width: box.width, height: halfHeight),
            CGRect(x: box.minX, y: box.minY + halfHeight, width: box.width, height: box.height - halfHeight),
        ]
    }

    /// Each half's sharpness now over the sharpness of the same content in the anchor: the
    /// half's rectangle moved by minus the offset, kept inside the frame. A half whose moved
    /// rectangle is less than half inside the frame has no ratio.
    private func focusRatios(
        of box: CGRect, current: BoxHalves, anchor: CVPixelBuffer, offset: CGPoint
    ) -> HalfFocus {
        let bounds = CGRect(
            x: 0, y: 0, width: CVPixelBufferGetWidth(anchor), height: CVPixelBufferGetHeight(anchor))
        func ratio(_ rect: CGRect, _ now: Double) -> Double? {
            let moved = rect.offsetBy(dx: -offset.x, dy: -offset.y).intersection(bounds)
            guard !moved.isNull else { return nil }
            let region = CGRect(
                x: moved.minX.rounded(.up), y: moved.minY.rounded(.up),
                width: moved.maxX.rounded(.down) - moved.minX.rounded(.up),
                height: moved.maxY.rounded(.down) - moved.minY.rounded(.up))
            guard region.width > 0, region.height > 0,
                region.width * region.height >= 0.5 * rect.width * rect.height,
                let reference = FrameAnalyzer.stats(of: anchor, in: region, step: Self.statsStep)
            else { return nil }
            return now / max(reference.sharpness, 1)
        }
        let rects = halfRects(of: box)
        return HalfFocus(
            left: ratio(rects[0], current.left), right: ratio(rects[1], current.right),
            top: ratio(rects[2], current.top), bottom: ratio(rects[3], current.bottom))
    }

    /// The sharpness of each half of the box, at `statsStep`, in whole pixels. A half that
    /// could not be measured reads as the whole box's.
    private func measureHalves(of box: CGRect, in buffer: CVPixelBuffer, fallback: Double) -> BoxHalves {
        func sharpness(_ rect: CGRect) -> Double {
            FrameAnalyzer.stats(of: buffer, in: rect, step: Self.statsStep)?.sharpness ?? fallback
        }
        let rects = halfRects(of: box)
        var halves = BoxHalves(
            left: sharpness(rects[0]), right: sharpness(rects[1]), top: sharpness(rects[2]),
            bottom: sharpness(rects[3]))
        // The four quarters, for telling a corner from a sparse patch.
        let started = ContinuousClock.now
        let halfWidth = (box.width / 2).rounded(.down)
        let halfHeight = (box.height / 2).rounded(.down)
        func quarter(_ column: Int, _ row: Int) -> Double {
            sharpness(
                CGRect(
                    x: box.minX + (column == 0 ? 0 : halfWidth),
                    y: box.minY + (row == 0 ? 0 : halfHeight),
                    width: column == 0 ? halfWidth : box.width - halfWidth,
                    height: row == 0 ? halfHeight : box.height - halfHeight))
        }
        halves.topLeft = quarter(0, 0)
        halves.topRight = quarter(1, 0)
        halves.bottomLeft = quarter(0, 1)
        halves.bottomRight = quarter(1, 1)
        let taken = ContinuousClock.now - started
        quarterMilliseconds =
            Double(taken.components.seconds) * 1000 + Double(taken.components.attoseconds) / 1e15
        return halves
    }

    // MARK: Reading

    private struct Outcome {
        var offset: CGPoint?
        var usedOffset: CGPoint?
        var frameShift: CGPoint?
        var reading = "missing"
        var streak = 0
        var event = HopOdometer.Event.none
        var agreement: Double?
        var blankReturnEvent = ""
        var chain: CGPoint?
        var chainGap: Double?
        var isGhost = false
    }

    private struct ReferenceReading {
        var match: CGPoint?
        var trueOffFields: Double?
        var errorFields: Double?
        var state = "none"
    }

    private static func side(of box: CGRect?, frameSize: CGSize) -> Double {
        box.map { Double(min($0.width, $0.height)) } ?? Double(min(frameSize.width, frameSize.height))
    }

    private func boxStats(_ buffer: CVPixelBuffer, _ whole: FrameStats?) -> FrameStats {
        let inside = box.flatMap { FrameAnalyzer.stats(of: buffer, in: $0, step: Self.statsStep) }
        return inside ?? whole ?? FrameAnalyzer.stats(of: buffer, step: Self.statsStep)
            ?? FrameStats(brightness: 0, sharpness: 0, contrast: 0)
    }

    private func reading(
        _ outcome: Outcome, boxStats: FrameStats, frameSize: CGSize, start: ReferenceReading
    ) -> SlideTrackerReading {
        // The box the movement is measured in sizes the hop limits and the distance unit.
        let referenceSide = box.map { Double(min($0.width, $0.height)) }
        let boxSide = referenceSide ?? Double(min(frameSize.width, frameSize.height))
        return SlideTrackerReading(
            boxStats: boxStats, frameShift: shownShift(outcome),
            anchorOffset: outcome.offset,
            usedOffset: outcome.usedOffset, position: odometer.position,
            positionFields: odometer.positionInFields(fieldSide: boxSide), boxSide: boxSide,
            hopLimit: odometer.hopDistance(frameSize: frameSize, referenceSide: referenceSide),
            hops: odometer.hops, gaps: odometer.gaps, isLost: odometer.isLost, event: outcome.event,
            hopAgreement: outcome.agreement, reading: outcome.reading,
            predictedStreak: outcome.streak, chain: outcome.chain, anchorChainGap: outcome.chainGap,
            hasDetail: detail.hasDetail,
            blindStretches: blindStretches, blankReturnsMatched: blankReturnsMatched,
            blankReturnsUnmatched: blankReturnsUnmatched,
            blankReturnEvent: outcome.blankReturnEvent, referenceMatch: start.match,
            trueOffReferenceFields: start.trueOffFields, trackerErrorFields: start.errorFields,
            pictureCheck: start.state)
    }

    // MARK: Tracking

    /// One tracked frame: the frame-to-frame shift, the detail check, and the reading against
    /// the anchor (or, after a stretch with nothing to track, the match of the held picture).
    private func trackFrame(
        _ buffer: CVPixelBuffer, seconds: Double, frameSize: CGSize, boxStats: FrameStats,
        features: FeatureCells?
    ) -> Outcome {
        var outcome = Outcome()
        frameIndex += 1
        let hadDetail = detail.hasDetail
        detail.update(boxSharpness: boxStats.sharpness, features: features)
        // A frame with detail on but almost no features cannot be registered: it is skipped like
        // a ghost (no shift, no anchor reading, the previous frame kept), and a run of them is
        // the no-detail pause.
        let nearEmpty =
            anchor != nil && detail.hasDetail && box != nil
            && (features?.cells ?? Int.max) < ghostThresholds.minFeatureCellsToRegister
            && boxStats.sharpness < ghostThresholds.maxSharpnessForSparseSkip
        if nearEmpty {
            sparseSkips += 1
            sparseRun += 1
            outcome.isGhost = true
            outcome.reading = "sparse_skip"
            if sparseRun >= ghostThresholds.maxSparseSkipsInARow {
                sparseRun = 0
                detail.forceNoDetail()
            }
        } else {
            sparseRun = 0
            var measuredShift = measureFrameShift(buffer)
            if let override = frameShiftOverride {
                measuredShift = override(frameIndex, measuredShift)
            }
            outcome.frameShift = acceptedShift(measuredShift, buffer, frameSize: frameSize, &outcome)
        }
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
        // A ghost frame changes nothing: no anchor reading, no chain, no odometer.
        guard !outcome.isGhost else { return outcome }

        let boxSide = Self.side(of: box, frameSize: frameSize)
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
                    committing: nil)
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
        if let box {
            verdict = consistency.judge(
                anchorOffset: measured, frameShift: outcome.frameShift,
                boxSide: Double(min(box.width, box.height)))
        } else if let measured {
            verdict = .measured(measured)
        }
        outcome.reading = verdict.csvName
        outcome.streak = consistency.predictedStreak
        outcome.chain = consistency.chain
        outcome.chainGap = consistency.lastChainGap
        outcome.usedOffset = verdict.offset
        var committing: CGPoint?
        if case .predicted(let predicted) = verdict, consistency.mustCommit {
            // Predictions have stood in for too long: trust them as a hop.
            committing = predicted
        }
        advance(
            &outcome, held: held, buffer: buffer, seconds: seconds, frameSize: frameSize,
            committing: committing)
        return outcome
    }

    /// Hands the odometer the offset to use, and re-anchors when it says so.
    private func advance(
        _ outcome: inout Outcome, held: CVPixelBuffer, buffer: CVPixelBuffer, seconds: Double,
        frameSize: CGSize, committing: CGPoint?
    ) {
        var result: (event: HopOdometer.Event, reanchor: Bool)
        if let committing {
            odometer.commit(offset: committing)
            result = (.hop, true)
        } else {
            result = odometer.update(
                offset: outcome.usedOffset, frameSize: frameSize,
                referenceSide: box.map { Double(min($0.width, $0.height)) })
        }
        outcome.event = result.event
        if outcome.event == .hop, measuresHopAgreement, let used = outcome.usedOffset,
            seconds - lastAgreementAt >= Self.agreementEverySeconds
        {
            lastAgreementAt = seconds
            outcome.agreement = agreement(from: held, to: buffer, offset: used)
        }
        if result.reanchor { anchorOn(buffer) }
    }

    // MARK: Reference picture check

    private func updateReference(
        _ buffer: CVPixelBuffer, frameShift: CGPoint?, boxSide: Double, frameSize: CGSize
    ) -> ReferenceReading {
        let rect = box ?? CGRect(origin: .zero, size: frameSize)
        if referenceRequested {
            referenceRequested = false
            if let copy = boxRegistration.copy(of: buffer, box: rect, context: context) {
                referencePicture = copy
                referenceBox = rect
                referencePosition = odometer.position
                referenceAccepted = nil
                referenceMisses = 0
                referenceReadings = 0
                referenceCheck.reset()
            }
        }
        guard let picture = referencePicture else { return ReferenceReading() }
        // The box moved (re-detected, adjusted, mode changed): the stored picture is no
        // longer the same patch of the view.
        guard rect == referenceBox else {
            clearReferencePicture()
            return ReferenceReading()
        }

        let moved = CGPoint(
            x: odometer.position.x - referencePosition.x,
            y: odometer.position.y - referencePosition.y)
        let limit = referenceCheck.thresholds.maxOffsetOfBox * boxSide
        guard detail.hasDetail, hypot(Double(moved.x), Double(moved.y)) <= limit else {
            referenceCheck.reset()
            referenceAccepted = nil
            return ReferenceReading(state: detail.hasDetail ? "out_of_range" : "matching")
        }

        var measured = boxRegistration.offset(fromStored: picture, to: buffer, box: rect)
        referenceReadings += 1
        if let override = referenceReadingOverride { measured = override(referenceReadings, measured) }
        if let accepted = referenceAccepted {
            // Confirmed: keep measuring, but accept only what agrees with the last accepted
            // reading plus the frame-to-frame movement.
            let expected = CGPoint(
                x: accepted.x + (frameShift?.x ?? 0), y: accepted.y + (frameShift?.y ?? 0))
            if let measured,
                hypot(Double(measured.x - expected.x), Double(measured.y - expected.y))
                    <= referenceCheck.thresholds.maxStepDisagreementOfBox * boxSide
            {
                referenceAccepted = measured
                referenceMisses = 0
            } else {
                referenceMisses += 1
                if referenceMisses >= referenceMissesToRecheck {
                    referenceAccepted = nil
                    referenceMisses = 0
                    referenceCheck.reset()
                    return ReferenceReading(state: "matching")
                }
                referenceAccepted = expected
            }
        } else {
            switch referenceCheck.feed(offset: measured, frameShift: frameShift, boxSide: boxSide) {
            case .confirmed(let offset):
                referenceAccepted = offset
            case .rejected:
                // Never agreed: start the check again from the next frame instead of staying
                // rejected until the view leaves range and comes back.
                referenceCheck.reset()
                return ReferenceReading(state: "matching")
            case .pending:
                return ReferenceReading(state: "matching")
            }
        }

        guard let match = referenceAccepted, boxSide > 0 else {
            return ReferenceReading(state: "matching")
        }
        return ReferenceReading(
            match: match, trueOffFields: hypot(Double(match.x), Double(match.y)) / boxSide,
            errorFields: hypot(Double(moved.x - match.x), Double(moved.y - match.y)) / boxSide,
            state: "confirmed")
    }

    // MARK: Hops

    private func anchorOn(_ buffer: CVPixelBuffer) {
        travel.hold(buffer)
        anchor = buffer
        consistency.reset()
    }

    /// The frame-to-frame shift. With a box, both frames are cropped to it; with the whole
    /// frame it is `ShakeEstimator`'s.
    private func measureFrameShift(_ buffer: CVPixelBuffer) -> CGPoint? {
        guard let box else {
            _ = shake.update(with: buffer)
            return shake.lastShift
        }
        shake.reset()
        guard let previousFrame else { return nil }
        return boxRegistration.offset(from: previousFrame, to: buffer, box: box)
    }

    /// The frame-to-frame shift this frame may use, and what to hold as the previous frame. A shift
    /// larger than `maxFrameShiftShareOfBox` of the box is a ghost: the frame is dropped and the
    /// previous frame stays the last good one, so the next frame registers against it. Ghosts
    /// `maxInARow` times in a row are taken as real: no shift is used, and the frame moves on.
    private func acceptedShift(
        _ measured: CGPoint?, _ buffer: CVPixelBuffer, frameSize: CGSize, _ outcome: inout Outcome
    ) -> CGPoint? {
        let side = Self.side(of: box, frameSize: frameSize)
        if box != nil, let measured,
            hypot(Double(measured.x), Double(measured.y))
                > ghostThresholds.maxFrameShiftShareOfBox * side
        {
            ghostFrames += 1
            ghostRun += 1
            if ghostRun >= ghostThresholds.maxInARow {
                // Real fast movement or a broken view: the missing-shift fallback.
                ghostFallbacks += 1
                ghostRun = 0
                previousFrame = buffer
                return nil
            }
            outcome.isGhost = true
            outcome.reading = "ghost"
            return nil
        }
        ghostRun = 0
        previousFrame = box == nil ? nil : buffer
        if let measured { lastGoodShake = measured }
        return measured
    }

    /// The frame-to-frame shift a reading reports. A ghost frame carries the last good one, so a
    /// speed spike does not show; a skipped near-empty frame reports none (zero), because carrying
    /// the last one made a helper who had stopped look in motion for as long as the picture stayed
    /// near empty, and the hold on an aligned spot never began.
    private func shownShift(_ outcome: Outcome) -> CGPoint? {
        guard outcome.isGhost else { return outcome.frameShift }
        return outcome.reading == "sparse_skip" ? .zero : lastGoodShake
    }

    private func measureAnchorOffset(held: CVPixelBuffer, current: CVPixelBuffer) -> CGPoint? {
        guard let box else { return travel.offset(to: current) }
        return boxRegistration.offset(from: held, to: current, box: box)
    }

    /// How well the two frames agree once the picture is moved by the hop.
    ///
    /// `offset` is the registered shift from `anchor` to `current`, which is what
    /// `PanoramaStitcher.contentShift` computes the same way (a request targeted at the
    /// earlier frame, run on the later one, vertical flipped). That function then asks for
    /// `agreement(movedBy: -shift)`, so this passes the NEGATED offset to match it.
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
