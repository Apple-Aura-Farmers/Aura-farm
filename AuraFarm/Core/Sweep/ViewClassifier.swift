import Foundation

/// What the box is looking at.
enum ViewClass: String, Equatable {
    case sample, thin, blank, blurry, dark
}

/// The numbers `ViewClassifier` decides with. Data, not logic. All PLACEHOLDER: not
/// calibrated. The sources are the 12 November 2026 mechanical stage runs, measured in the
/// box on the lab scale (every 4th pixel).
struct ViewClassifierThresholds {
    /// Box brightness below this is too dark to judge. A guess: nothing this dark was
    /// measured.
    var darkBelowBrightness: Double = 40
    /// Box sharpness below this is too little detail to follow. Keep equal to
    /// `DetailThresholds.minBoxSharpness`. Blank or very sparse glass read 6–100, sparse
    /// sample 120–280.
    var lowDetailBelowSharpness: Double = 120
    /// Box sharpness below this (and above the low-detail limit) is thin sample. Sparse
    /// sample read 120–280; dense sample 1,000–3,800.
    var thinBelowSharpness: Double = 300
    /// Low-detail glass this much brighter than the sample baseline is blank rather than
    /// blurry. Blank patches read about 205–220 against 165–190 over sample, at the same
    /// exposure.
    var blankBrightnessRatio: Double = 1.15
    /// The same test before any sample has been seen to make a baseline.
    var blankFallbackBrightness: Double = 195
    /// Sample readings kept for the brightness baseline (their median).
    var baselineReadings: Int = 20
    /// Consecutive readings of a new class before the reported class changes, like
    /// `CaptureQualityMonitor`'s streaks.
    var readingsToChange: Int = 3
}

/// Says what the registration box shows: sample, thin sample, blank glass, blur or too dark.
///
/// Contrast is accepted and logged by callers but NOT used here: whole-frame contrast was
/// meaningless because of the eyepiece ring, and box contrast is unproven.
struct ViewClassifier {
    var thresholds: ViewClassifierThresholds

    /// The class of the latest reading alone.
    private(set) var rawClass = ViewClass.sample
    /// The reported class, which changes only after `readingsToChange` agreeing readings. The
    /// first reading sets it directly.
    private(set) var current = ViewClass.sample
    private(set) var hasReading = false

    private var sampleBrightness: [Double] = []
    private var candidate: ViewClass?
    private var candidateStreak = 0

    init(thresholds: ViewClassifierThresholds = ViewClassifierThresholds()) {
        self.thresholds = thresholds
    }

    /// The median brightness of recent sample readings; nil before there are any.
    var baseline: Double? {
        guard !sampleBrightness.isEmpty else { return nil }
        let sorted = sampleBrightness.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    @discardableResult
    mutating func update(brightness: Double, sharpness: Double, contrast: Double) -> ViewClass {
        _ = contrast
        let raw = classify(brightness: brightness, sharpness: sharpness)
        rawClass = raw
        if raw == .sample {
            sampleBrightness.append(brightness)
            if sampleBrightness.count > thresholds.baselineReadings {
                sampleBrightness.removeFirst(sampleBrightness.count - thresholds.baselineReadings)
            }
        }

        if !hasReading {
            hasReading = true
            current = raw
        } else if raw == current {
            candidate = nil
            candidateStreak = 0
        } else {
            candidateStreak = candidate == raw ? candidateStreak + 1 : 1
            candidate = raw
            if candidateStreak >= thresholds.readingsToChange {
                current = raw
                candidate = nil
                candidateStreak = 0
            }
        }
        return current
    }

    mutating func reset() {
        self = ViewClassifier(thresholds: thresholds)
    }

    private func classify(brightness: Double, sharpness: Double) -> ViewClass {
        if brightness < thresholds.darkBelowBrightness { return .dark }
        if sharpness < thresholds.lowDetailBelowSharpness {
            let limit =
                baseline.map { $0 * thresholds.blankBrightnessRatio }
                ?? thresholds.blankFallbackBrightness
            return brightness >= limit ? .blank : .blurry
        }
        if sharpness < thresholds.thinBelowSharpness { return .thin }
        return .sample
    }
}
