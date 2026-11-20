import CoreGraphics
import Foundation

/// The numbers `AlignmentCheck` decides with. Data, not logic. All PLACEHOLDER: not
/// calibrated; calibrate from the setup log (`alignment` columns).
struct AlignmentThresholds {
    /// The bright area is under this share of the frame: no circle found.
    var minCircleShareOfFrame: Double = 0.05
    /// The share of the frame border's grid cells that belong to the bright region, above
    /// which the circle is cut off by the frame.
    var maxBorderTouchShare: Double = 0.02
    /// Bright area over the area of the circle that just encloses it (centred on the region's
    /// centroid). A crescent or an eclipse is lower.
    var minRoundness: Double = 0.85
    /// Angular sectors of the circle, measured inside `sectorRadiusShare` of its radius.
    var sectorCount: Int = 8
    var sectorRadiusShare: Double = 0.8
    /// The darkest sector's mean over the brightest sector's.
    var minEvenness: Double = 0.75
    /// A grid cell at or above this luma is saturated.
    var saturatedLuma: Int = 250
    /// The share of grid cells inside the circle that may be saturated.
    var maxSaturatedShare: Double = 0.01
    /// The brightest sector's mean over the median sector mean.
    var maxGlareRatio: Double = 1.25
    /// Every check must pass this long without a break.
    var passSeconds: Double = 1.5
    /// A score change under this many points counts as steady.
    var trendDeadBand: Double = 3
    /// How long ago the trend compares the score with.
    var trendSeconds: Double = 2

    // Losing alignment after it passed uses LOOSER limits than passing (hysteresis), so a
    // reading just under the pass limits does not send the helper back. PLACEHOLDER: not
    // calibrated; calibrate from the setup log.
    var lostMinRoundness: Double = 0.78
    var lostMinEvenness: Double = 0.65
    var lostMaxGlareRatio: Double = 1.4
    var lostMaxBorderTouchShare: Double = 0.04
    /// The circle's centre moved this share of its radius from the last passing circle.
    var lostCentreShiftShareOfRadius: Double = 0.10
    /// A frame with no circle counts as failing. Failing this long without a break is lost.
    var lostSeconds: Double = 2.0

    // Once the field circle is confirmed (focus step), a loss is judged on GEOMETRY ONLY:
    // evenness and glare move by themselves while the focus knob turns. PLACEHOLDER; source:
    // the user's report that the check was far too sensitive.
    var confirmedLostMinRoundness: Double = 0.70
    var confirmedLostCentreShiftShareOfRadius: Double = 0.18
    var confirmedLostRadiusChange: Double = 0.15
    var confirmedLostSeconds: Double = 3.0
}

/// A side of the camera frame, in FRAME axes (top-down pixels).
enum FrameSide: Hashable, CaseIterable {
    case top, bottom, left, right
}

/// What is wrong with how the phone sits over the eyepiece, worst first.
enum AlignmentProblem: Equatable {
    case noCircle, clipped, notRound, uneven, glare

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .noCircle: "no_circle"
        case .clipped: "clipped"
        case .notRound: "not_round"
        case .uneven: "uneven"
        case .glare: "glare"
        }
    }
}

enum AlignmentTrend: Equatable {
    case better, worse, steady
}

/// What one frame says about the phone's alignment.
struct AlignmentReading: Equatable {
    var found = false
    /// The circle fitted to the bright region (its centroid, the radius from its area), in
    /// frame pixels.
    var circle: FieldCircle?
    /// The frame edges the bright region touches beyond `maxBorderTouchShare`.
    var clippedSides: Set<FrameSide> = []
    var roundness: Double?
    /// The largest share of the frame border's cells that the bright region covers on one
    /// side; `clippedSides` is the sides above `maxBorderTouchShare`.
    var borderTouchShare = 0.0
    /// The mean luma of each sector of the circle. Sector 0 is centred on frame +x; sectors go
    /// clockwise in top-down frame coordinates (so sector 2 points down the frame, sector 4
    /// along -x, sector 6 up).
    var sectorMeans: [Double] = []
    var evenness: Double?
    var darkestSector: Int?
    var brightestSector: Int?
    var saturatedShare: Double?
    var glareRatio: Double?
    /// Ordered worst first: no circle, clipped, not round, uneven, glare.
    var problems: [AlignmentProblem] = []
    /// 0...100. Each check gets a margin from 0 (at its limit or worse) to 1 (well inside):
    /// circle share (limit to twice the limit), border touch (the limit to none), roundness
    /// (its minimum to 1), evenness (its minimum to 1), saturated share (the limit to none) and
    /// glare ratio (its maximum to 1). The score is 100 times half the smallest margin plus half
    /// the mean margin: one bad check drags it down, but not to zero while the rest is fine. 0
    /// when no circle is found.
    var score = 0.0

    var passes: Bool { found && problems.isEmpty }
}
