import Foundation

/// Checks, frame by frame, that the phone sits well over the eyepiece: the whole bright circle
/// is in the frame, round, evenly lit and free of glare. A phone just clamped to the eyepiece
/// is usually off-centre or tilted, which shows as a circle cut off by the frame, a misshapen
/// one, one side darker, or a glare patch. Works on the luma grid the mask learner uses, so it
/// is cheap enough to run on every analyzed frame. One instance per session, one serial queue.
struct AlignmentCheck {
    var thresholds: AlignmentThresholds

    private var passingSince: Double?
    private var failingSince: Double?
    private var lastPassingCircle: FieldCircle?
    /// Alignment has been passed: the reference circle is kept from then on, so a tidy circle
    /// that has moved is still lost.
    private var hasPassed = false
    private var lastSeconds: Double?
    private var history: [(seconds: Double, score: Double)] = []

    init(thresholds: AlignmentThresholds = AlignmentThresholds()) {
        self.thresholds = thresholds
    }

    /// Every check has passed for `passSeconds` without a break.
    var isPassed: Bool {
        guard let passingSince, let lastSeconds else { return false }
        return lastSeconds - passingSince >= thresholds.passSeconds - 1e-9
    }

    /// Alignment that had passed has been lost: the looser `lost*` limits have failed for
    /// `lostSeconds` without a break (a frame with no circle fails). Judged against the last
    /// circle that passed, so a shifted but still tidy circle is lost too.
    var isLost: Bool {
        guard let failingSince, let lastSeconds else { return false }
        return lastSeconds - failingSince >= thresholds.lostSeconds - 1e-9
    }

    /// The score now against about `trendSeconds` ago; steady within the dead band, or while
    /// there is under a second of history.
    var trend: AlignmentTrend {
        guard let last = history.last, let first = history.first,
            last.seconds - first.seconds >= 1
        else { return .steady }
        let target = last.seconds - thresholds.trendSeconds
        let before = history.last { $0.seconds <= target } ?? first
        let change = last.score - before.score
        if change > thresholds.trendDeadBand { return .better }
        if change < -thresholds.trendDeadBand { return .worse }
        return .steady
    }

    mutating func update(
        luma: [UInt8], gridWidth: Int, gridHeight: Int, gridStep: Int, seconds: Double
    ) -> AlignmentReading {
        let reading = AlignmentMeasure.measure(
            luma: luma, gridWidth: gridWidth, gridHeight: gridHeight, gridStep: gridStep,
            thresholds: thresholds)
        lastSeconds = seconds
        if reading.passes {
            passingSince = passingSince ?? seconds
            if !hasPassed { lastPassingCircle = reading.circle }
        } else {
            passingSince = nil
        }
        if isPassed { hasPassed = true }
        if fails(reading) {
            failingSince = failingSince ?? seconds
        } else {
            failingSince = nil
        }
        history.append((seconds, reading.score))
        history.removeAll { seconds - $0.seconds > thresholds.trendSeconds + 1 }
        return reading
    }

    /// Whether one reading is outside the looser limits.
    private func fails(_ reading: AlignmentReading) -> Bool {
        guard reading.found, let circle = reading.circle else { return true }
        if (reading.roundness ?? 0) < thresholds.lostMinRoundness
            || (reading.evenness ?? 0) < thresholds.lostMinEvenness
            || (reading.glareRatio ?? 1) > thresholds.lostMaxGlareRatio
            || reading.borderTouchShare > thresholds.lostMaxBorderTouchShare
        {
            return true
        }
        guard let reference = lastPassingCircle else { return false }
        let shift = hypot(
            Double(circle.centre.x - reference.centre.x), Double(circle.centre.y - reference.centre.y))
        return shift > thresholds.lostCentreShiftShareOfRadius * reference.radius
    }

    mutating func reset() {
        failingSince = nil
        lastPassingCircle = nil
        hasPassed = false
        passingSince = nil
        lastSeconds = nil
        history = []
    }
}
