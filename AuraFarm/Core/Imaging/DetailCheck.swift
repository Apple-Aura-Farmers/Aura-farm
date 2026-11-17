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

    // Sparse sample: a few distinct particles on bright glass average to a low variance, yet the
    // picture has plenty to follow. Source: failed_edge_detection.csv and the 16 Nov 2026 stage
    // step, where coarse structure stayed while the fine variance fell. All PLACEHOLDER.
    /// Whether the sparse rule is used at all (the lab's "Track sparse sample").
    var tracksSparse = true
    /// A pixel is a feature when its |Laplacian| is at least this, in luma units.
    var featureContrast: Double = 40
    /// The sparse rule still needs this much box sharpness (blank glass is about 17).
    var sparseFloorSharpness: Double = 30
    var minFeatureCells = 4
    /// ... spread over at least this many of the box's 4 quarters.
    var minFeatureQuarters = 2
}

/// Whether the registration box holds enough detail to follow. Over empty glass registration
/// has nothing to lock onto and reads about 0, which looks like "not moving"; this says so
/// instead. Debounced with streaks, like `CaptureQualityMonitor`.
struct DetailCheck {
    var thresholds: DetailThresholds
    private(set) var hasDetail = true
    /// This reading was followed only because of the sparse rule (variance under the limit).
    private(set) var isSparse = false
    private var lowStreak = 0
    private var highStreak = 0

    init(thresholds: DetailThresholds = DetailThresholds()) {
        self.thresholds = thresholds
    }

    /// - Parameter features: the box's feature cells; nil leaves only the sharpness rule.
    mutating func update(boxSharpness: Double, features: FeatureCells? = nil) {
        let plain = boxSharpness >= thresholds.minBoxSharpness
        let sparse =
            thresholds.tracksSparse && !plain && boxSharpness >= thresholds.sparseFloorSharpness
            && (features?.cells ?? 0) >= thresholds.minFeatureCells
            && (features?.quarters ?? 0) >= thresholds.minFeatureQuarters
        isSparse = sparse
        let detailed = plain || sparse
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

    /// Puts the check into "no detail" at once, for a run of frames too empty to register; detail
    /// comes back by the usual streak.
    mutating func forceNoDetail() {
        hasDetail = false
        isSparse = false
        lowStreak = 0
        highStreak = 0
    }

    mutating func reset() {
        self = DetailCheck(thresholds: thresholds)
    }
}
