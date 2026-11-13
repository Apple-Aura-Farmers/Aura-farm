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
    /// The frame the travel is measured from. The same buffer `travel` holds, kept here as
    /// well because a hop's agreement needs both frames as images.
    private var anchor: CVPixelBuffer?
    private lazy var context = CIContext(options: [.useSoftwareRenderer: false])
    private var lastAgreementAt = -Double.infinity
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
        pictureMatch: PictureMatchThresholds = PictureMatchThresholds()
    ) {
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
        let outcome = trackFrame(buffer, seconds: seconds, frameSize: frameSize, boxStats: stats)
        let boxSide = Self.side(of: box, frameSize: frameSize)
        let start = updateReference(
            buffer, frameShift: outcome.frameShift, boxSide: boxSide, frameSize: frameSize)
        return reading(outcome, boxStats: stats, frameSize: frameSize, start: start)
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
            boxStats: boxStats, frameShift: outcome.frameShift, anchorOffset: outcome.offset,
            usedOffset: outcome.usedOffset, position: odometer.position,
            positionFields: odometer.positionInFields(fieldSide: boxSide), boxSide: boxSide,
            hopLimit: odometer.hopDistance(frameSize: frameSize, referenceSide: referenceSide),
            hops: odometer.hops, gaps: odometer.gaps, isLost: odometer.isLost, event: outcome.event,
            hopAgreement: outcome.agreement, reading: outcome.reading,
            predictedStreak: outcome.streak, hasDetail: detail.hasDetail,
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
        _ buffer: CVPixelBuffer, seconds: Double, frameSize: CGSize, boxStats: FrameStats
    ) -> Outcome {
        var outcome = Outcome()
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
        defer { previousFrame = box == nil ? nil : buffer }
        guard let box else {
            _ = shake.update(with: buffer)
            return shake.lastShift
        }
        shake.reset()
        guard let previousFrame else { return nil }
        return boxRegistration.offset(from: previousFrame, to: buffer, box: box)
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
