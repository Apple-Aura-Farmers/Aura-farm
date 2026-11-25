import Foundation

/// The numbers `FocusGuide` decides with. Data, not logic. All PLACEHOLDER: calibrate from the
/// setup log (`focus_*` columns).
struct FocusThresholds {
    /// The sharpness used is the median of this many readings, so a shake of the phone is not
    /// the best seen.
    var smoothingReadings: Int = 5
    /// Lab scale (`FrameAnalyzer.stats` at step 4). A peak above this is enough sample by itself.
    /// Source: E1, soil inside the cover slip read median 489 and 10th percentile 194.
    var minPeakSharpness: Double = 150
    /// A sparse view peaks lower: it counts from this peak on, when turning the knob changed the
    /// sharpness by `sparsePeakRise` (an empty view hardly changes). PLACEHOLDER: the operator,
    /// 24 Nov: a sharp sparse view was never accepted.
    var sparsePeakSharpness: Double = 40
    /// The peak over the lowest value seen.
    var sparsePeakRise: Double = 1.5
    /// This long at one spot without a single tiles reading of `minActiveTiles` or more active
    /// tiles, and no peak good enough to accept: ask to move to sample. Once the spot has shown
    /// enough it never asks, however far the knob is turned away. Replaces the old 8 s trigger.
    /// PLACEHOLDER; source: "25 Nov 100x logs".
    var noSampleSeconds: Double = 12
    /// A tiles reading with this many active tiles is enough sample. PLACEHOLDER; source:
    /// "25 Nov 100x logs".
    var minActiveTiles: Int = 8
    /// Current below this share of the peak, after the peak: passed it.
    var passedFraction: Double = 0.55
    /// Current at or above this share of the peak: near the best.
    var nearFraction: Double = 0.75
    /// Near the best and steady for this long: focused.
    var settleSeconds: Double = 0.6
    /// Steady: the standard deviation of the smoothed readings over `settleSeconds`, as a share
    /// of the peak, is under this.
    var settleVariation: Double = 0.15
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
/// 1. Starts in `turnOneWay`, keeping the peak. 2. Once the peak is a real one (`hasSample`)
/// and the current value falls below `passedFraction` of it: `passedPeak`. 3. From there,
/// back to `nearFraction` of the peak: `nearPeak`. 4. Near the best and steady for
/// `settleSeconds`: `focused`, which stays. 5. `needsSample` when the peak is not a real one and,
/// after `noSampleSeconds` at this spot, no tiles reading had `minActiveTiles` active tiles; it
/// clears as soon as one does, or the peak becomes a real one. 6. A new peak in `nearPeak` just
/// raises the peak. Falling under `passedFraction` again from `nearPeak` is `passedPeak` again, so
/// overshooting twice works.
struct FocusGuide {
    var thresholds: FocusThresholds

    private var window: [Double] = []
    private(set) var peak = 0.0
    /// The lowest smoothed value seen, for the peak of a sparse view.
    private(set) var lowest = Double.infinity
    private var state = FocusGuideState.turnOneWay
    private(set) var startedAt: Double?
    /// A tiles reading at this spot had enough active tiles.
    private var sawEnough = false
    private var settling: [(seconds: Double, value: Double)] = []

    init(thresholds: FocusThresholds = FocusThresholds()) {
        self.thresholds = thresholds
    }

    /// - Parameter activeTiles: the active tile count of the latest `FocusTiles` reading; nil on a
    ///   frame without one, which changes nothing.
    mutating func update(
        sharpness: Double, seconds: Double, activeTiles: Int? = nil
    ) -> FocusReading {
        startedAt = startedAt ?? seconds
        if let activeTiles, activeTiles >= thresholds.minActiveTiles { sawEnough = true }
        window.append(sharpness)
        if window.count > max(thresholds.smoothingReadings, 1) { window.removeFirst() }
        let sorted = window.sorted()
        let current = sorted[sorted.count / 2]
        peak = max(peak, current)
        lowest = min(lowest, current)

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

    /// The peak is a real one: high enough by itself, or clearly above the rest of the sweep.
    var hasSample: Bool {
        peak > thresholds.minPeakSharpness
            || peak > thresholds.sparsePeakSharpness && peak >= thresholds.sparsePeakRise * lowest
    }

    private mutating func advance(current: Double, seconds: Double) {
        guard hasSample else {
            if sawEnough {
                if state == .needsSample { state = .turnOneWay }
            } else if seconds - (startedAt ?? seconds) >= thresholds.noSampleSeconds {
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

extension FocusGuide {
    /// Every condition of setup's focus check that is not met, as short names; empty when the check
    /// accepts. The check: the guide `focused`, no fade since, and (on the guided page) confirmed.
    /// Pure: reads the guide's state, changes nothing. `reading` is the latest one, nil without.
    static func whyNot(
        _ guide: FocusGuide, reading: FocusReading?, faded: Bool, awaitsConfirm: Bool
    ) -> [String] {
        var reasons: [String] = []
        if let reading {
            let t = guide.thresholds
            if !guide.hasSample {
                // Not a real peak: too low, or (sparse) the sweep did not change it enough.
                let rises = guide.peak > t.sparsePeakSharpness
                reasons.append(rises ? "rise_too_small" : "peak_too_low")
            } else if reading.state == .turnOneWay {
                reasons.append("never_passed_peak")
            }
            if reading.state != .focused, reading.level < t.nearFraction { reasons.append("below_near") }
            if reading.state == .nearPeak { reasons.append("not_steady") }
        } else {
            reasons.append("no_reading")
        }
        if faded { reasons.append("faded") }
        if awaitsConfirm { reasons.append("not_confirmed") }
        return reasons
    }
}
