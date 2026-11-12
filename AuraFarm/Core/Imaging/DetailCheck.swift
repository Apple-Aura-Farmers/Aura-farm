import Foundation

/// The numbers `DetailCheck` decides with. Data, not logic.
struct DetailThresholds {
    /// Box sharpness (variance of the Laplacian, sampled every 4th pixel) below this means
    /// too little detail to follow. PLACEHOLDER: not calibrated. Whole-frame readings were
    /// about 55 over blank glass and 260–600 over sample; the whole-frame number includes the
    /// eyepiece ring's edge, so the box numbers should come out lower on both. 120 sits
    /// between the two, well clear of blank. Re-measure with the box stats in the CSV.
    var minBoxSharpness: Double = 120
    /// Readings in a row below the limit before detail counts as gone, and at or above it
    /// before detail counts as back. PLACEHOLDER: not calibrated.
    var readingsToRaise: Int = 3
    var readingsToClear: Int = 3
}

/// Whether the registration box holds enough detail to follow. Over empty glass registration
/// has nothing to lock onto and reads about 0, which looks like "not moving"; this says so
/// instead. Debounced with streaks, like `CaptureQualityMonitor`.
struct DetailCheck {
    var thresholds: DetailThresholds
    private(set) var hasDetail = true
    private var lowStreak = 0
    private var highStreak = 0

    init(thresholds: DetailThresholds = DetailThresholds()) {
        self.thresholds = thresholds
    }

    mutating func update(boxSharpness: Double) {
        let detailed = boxSharpness >= thresholds.minBoxSharpness
        if hasDetail {
            lowStreak = detailed ? 0 : lowStreak + 1
            if lowStreak >= thresholds.readingsToRaise {
                hasDetail = false
                lowStreak = 0
                highStreak = 0
            }
        } else {
            highStreak = detailed ? highStreak + 1 : 0
            if highStreak >= thresholds.readingsToClear {
                hasDetail = true
                lowStreak = 0
                highStreak = 0
            }
        }
    }

    mutating func reset() {
        self = DetailCheck(thresholds: thresholds)
    }
}
