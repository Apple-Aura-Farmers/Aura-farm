import Foundation

/// The numbers `ColumnCount` decides with. Data, not logic.
struct ColumnCountThresholds: Equatable {
    /// The slip's side in fields (the 22 mm square cover slip). PLACEHOLDER; source: the
    /// top-to-bottom leg heights of the 21:38, 22:12 and 22:51 runs, 13.6 to 15.1 fields.
    var slipFields = 14.2
    /// How far the first and last columns sit inside the slip's edges, in fields. The same as
    /// `GuidedSweepThresholds.columnInsetFields`, copied so this stays a plain value.
    var columnInsetFields = 0.6
}

/// How many columns the run will have, for "Column 3 of 9". No time estimate anywhere.
struct ColumnCount: Equatable {
    var thresholds = ColumnCountThresholds()

    /// N = floor((slip - 2 x inset) / step) + 1, for the square slip.
    func total(step: Double, slipFields: Double? = nil) -> Int {
        guard step > 0 else { return 1 }
        let side = slipFields ?? thresholds.slipFields
        let columns = ((side - 2 * thresholds.columnInsetFields) / step + 1e-9).rounded(.down) + 1
        return max(Int(columns), 1)
    }

    /// The count to show.
    /// - Parameters:
    ///   - step: fields between columns (1.6 or 0.8).
    ///   - measuredHeightFields: the slip's height once column 1 has a confirmed top and bottom
    ///     edge; the slip is square, so that is its width too.
    ///   - column: the column being swept.
    ///   - isLastColumn: the last column, or the right edge, was found: the count is real.
    func shown(step: Double, measuredHeightFields: Double?, column: Int, isLastColumn: Bool) -> Int {
        if isLastColumn { return max(column, 1) }
        let estimate = total(step: step, slipFields: measuredHeightFields)
        // A column past the estimate means the estimate was short; never "Column 10 of 9".
        return max(estimate, column)
    }
}

/// How fast the slide is moving against what the spot rule allows.
enum SpeedBand: Equatable {
    case green, amber, red

    /// - Parameters:
    ///   - speedFraction: `MovementIndicators.speedFraction`.
    ///   - nearCross: a spot is within `SpeedBandThresholds.nearCrossFields` of the cross, where
    ///     only a brief touch is allowed.
    static func of(
        speedFraction: Double, nearCross: Bool,
        thresholds: SpeedBandThresholds = SpeedBandThresholds()
    ) -> SpeedBand {
        if speedFraction >= thresholds.tooFastSpeedFraction { return .red }
        let limit =
            nearCross ? thresholds.maxTouchSpeedFraction : thresholds.comfortableSpeedFraction
        return speedFraction > limit ? .amber : .green
    }

    /// "Slower" shows with amber or red.
    var asksForSlower: Bool { self != .green }
}

/// The existing limits, gathered. Nothing new: each value is the one the guide already uses.
struct SpeedBandThresholds {
    /// `BriefTouchThresholds.maxTouchSpeedFraction`.
    var maxTouchSpeedFraction = BriefTouchThresholds().maxTouchSpeedFraction
    /// `MovementIndicatorThresholds.comfortableSpeedFraction`.
    var comfortableSpeedFraction = MovementIndicatorThresholds().comfortableSpeedFraction
    /// `MovementIndicatorThresholds.tooFastSpeedFraction`.
    var tooFastSpeedFraction = MovementIndicatorThresholds().tooFastSpeedFraction
    /// "Within 0.5 field of the cross": the same as the lab's "Ease off at the cross". The
    /// guide's own `GuideDryRun.easeOffFields` is private to the lab, so it is repeated here.
    var nearCrossFields = 0.5
}
