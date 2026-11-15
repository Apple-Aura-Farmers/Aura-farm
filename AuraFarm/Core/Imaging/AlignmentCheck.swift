import Foundation

/// Checks, frame by frame, that the phone sits well over the eyepiece: the whole bright circle
/// is in the frame, round, evenly lit and free of glare. A phone just clamped to the eyepiece
/// is usually off-centre or tilted, which shows as a circle cut off by the frame, a misshapen
/// one, one side darker, or a glare patch. Works on the luma grid the mask learner uses, so it
/// is cheap enough to run on every analyzed frame. One instance per session, one serial queue.
struct AlignmentCheck {
    var thresholds: AlignmentThresholds

    private var passingSince: Double?
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
        } else {
            passingSince = nil
        }
        history.append((seconds, reading.score))
        history.removeAll { seconds - $0.seconds > thresholds.trendSeconds + 1 }
        return reading
    }

    mutating func reset() {
        passingSince = nil
        lastSeconds = nil
        history = []
    }
}
