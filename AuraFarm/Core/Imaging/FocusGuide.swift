import Foundation

/// The numbers `FocusGuide` decides with. Data, not logic. All PLACEHOLDER: calibrate from the
/// setup log (`focus_*` columns).
struct FocusThresholds {
    /// The sharpness used is the median of this many readings.
    var smoothingReadings: Int = 3
    /// Lab scale (`FrameAnalyzer.stats` at step 4). A peak below this means there is not enough
    /// sample in view. Source: E1, soil inside the cover slip read median 489 and 10th
    /// percentile 194.
    var minPeakSharpness: Double = 150
    /// A sweep this long with no peak above `minPeakSharpness`: ask to move to sample.
    var sweepSecondsBeforeNoSample: Double = 8
    /// Current below this share of the peak, after the peak: passed it.
    var passedFraction: Double = 0.7
    /// Current at or above this share of the peak: near the best.
    var nearFraction: Double = 0.9
    /// Near the best and steady for this long: focused.
    var settleSeconds: Double = 1.0
    /// Steady: the standard deviation of the smoothed readings over `settleSeconds`, as a share
    /// of the peak, is under this.
    var settleVariation: Double = 0.08
}

enum FocusGuideState: Equatable {
    case turnOneWay, passedPeak, nearPeak, focused, needsSample

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .turnOneWay: "turn_one_way"
        case .passedPeak: "passed_peak"
        case .nearPeak: "near_peak"
        case .focused: "focused"
        case .needsSample: "needs_sample"
        }
    }
}

struct FocusReading: Equatable {
    var state: FocusGuideState
    /// The smoothed sharpness now, and the highest smoothed value seen.
    var current: Double
    var peak: Double
    /// current / peak, 0...1.
    var level: Double
}

/// Guides the helper to the sharpest image as they turn the microscope's focus knob. The
/// phone camera's own focus stays fixed; the best focus is the PEAK of sharpness over the
/// helper's sweep, because absolute sharpness depends on the sample.
///
/// 1. Starts in `turnOneWay`, keeping the peak. 2. Once the peak exceeds `minPeakSharpness`
/// and the current value falls below `passedFraction` of it: `passedPeak`. 3. From there,
/// back to `nearFraction` of the peak: `nearPeak`. 4. Near the best and steady for
/// `settleSeconds`: `focused`, which stays. 5. `needsSample` when the sweep runs
/// `sweepSecondsBeforeNoSample` with the peak never above the minimum; it clears as soon as
/// the peak rises above it. 6. A new peak in `nearPeak` just raises the peak. Falling under
/// `passedFraction` again from `nearPeak` is `passedPeak` again, so overshooting twice works.
struct FocusGuide {
    var thresholds: FocusThresholds

    private var window: [Double] = []
    private var peak = 0.0
    private var state = FocusGuideState.turnOneWay
    private var startedAt: Double?
    private var settling: [(seconds: Double, value: Double)] = []

    init(thresholds: FocusThresholds = FocusThresholds()) {
        self.thresholds = thresholds
    }

    mutating func update(sharpness: Double, seconds: Double) -> FocusReading {
        startedAt = startedAt ?? seconds
        window.append(sharpness)
        if window.count > max(thresholds.smoothingReadings, 1) { window.removeFirst() }
        let sorted = window.sorted()
        let current = sorted[sorted.count / 2]
        peak = max(peak, current)

        if state != .focused {
            advance(current: current, seconds: seconds)
        }
        return FocusReading(
            state: state, current: current, peak: peak,
            level: peak > 0 ? min(max(current / peak, 0), 1) : 0)
    }

    mutating func reset() {
        self = FocusGuide(thresholds: thresholds)
    }

    private mutating func advance(current: Double, seconds: Double) {
        guard peak > thresholds.minPeakSharpness else {
            if seconds - (startedAt ?? seconds) >= thresholds.sweepSecondsBeforeNoSample {
                state = .needsSample
            }
            return
        }
        if state == .needsSample { state = .turnOneWay }
        let passed = current < thresholds.passedFraction * peak
        switch state {
        case .turnOneWay:
            if passed { state = .passedPeak }
        case .passedPeak:
            if current >= thresholds.nearFraction * peak {
                state = .nearPeak
                settling = []
            }
        case .nearPeak:
            if passed {
                state = .passedPeak
                settling = []
            } else if isSteady(current: current, seconds: seconds) {
                state = .focused
            }
        case .focused, .needsSample:
            break
        }
    }

    /// Near the best and steady for `settleSeconds`: the readings over that long have a mean
    /// near the peak and vary little. Noise is the standard deviation, so one stray reading in
    /// a noisy stream does not restart the wait.
    private mutating func isSteady(current: Double, seconds: Double) -> Bool {
        settling.append((seconds, current))
        while settling.count > 1, settling[1].seconds <= seconds - thresholds.settleSeconds {
            settling.removeFirst()
        }
        guard let first = settling.first,
            seconds - first.seconds >= thresholds.settleSeconds - 1e-9
        else { return false }
        let values = settling.map(\.value)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return mean >= thresholds.nearFraction * peak
            && variance.squareRoot() / peak < thresholds.settleVariation
    }
}
