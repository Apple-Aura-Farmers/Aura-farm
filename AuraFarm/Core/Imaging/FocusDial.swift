import Foundation

/// The numbers `FocusDial` decides with. Data, not logic. All PLACEHOLDER: calibrate from the
/// `focus_dial_*` columns of the setup log and the movement CSV.
struct FocusDialThresholds {
    /// A drop of this share below a local maximum means the knob went past the peak (or, from
    /// past, back across it), and a fall this far below the value at the pause start means the
    /// wrong way when the side is not known.
    var passDropShare = 0.10
    /// The local maximum must have reached this share of the target to count as "near" it.
    var nearShare = 0.85
    /// "Almost there" shows this far outside the green zone.
    var almostBand = 0.15
}

enum FocusDialSide: String, Equatable {
    case approaching, past, unknown
}

/// What the focus dial shows after one reading.
struct FocusDialReading: Equatable {
    /// -1...1: 0 is at the target; negative is not far enough, positive too far.
    var offset: Double
    var side: FocusDialSide
    /// Half the width of the green zone on the same scale (1 minus the share that counts as
    /// sharp).
    var greenHalfWidth: Double
    var isGreen: Bool
    /// The side was not known and the value fell: the other way is the right one.
    var isWrongWay: Bool
    var message: String

    /// A short word for the CSV.
    var csvSide: String { isWrongWay ? "wrong_way" : side.rawValue }
}

/// A two-sided gauge for the Z knob. Sharpness alone cannot say which side of focus the knob is
/// on, but the sweep can: dropping after a peak means the knob went past it. Pure.
///
/// In setup the target is the highest value seen (`raisesTarget`) and the side starts as
/// approaching. In a run pause the target is the baseline and the side starts unknown, until
/// the value rises (approaching) or falls (wrong way).
struct FocusDial {
    var thresholds: FocusDialThresholds
    private(set) var target: Double?
    private let raisesTarget: Bool
    private let greenHalfWidth: Double
    private var side: FocusDialSide
    private var startValue: Double?
    private var localMax = 0.0
    /// After the first flip: the lowest value since the last flip (or since a new low), so a
    /// flip back needs a real rise first, not the fall that caused the flip.
    private var low = Double.infinity
    private var flipped = false

    /// - Parameters:
    ///   - goodShare: the share of the target that counts as sharp; the green zone's half width
    ///     is 1 minus it.
    ///   - startsUnknown: the run pause: nothing is known about which side the knob is on.
    init(
        target: Double?, goodShare: Double, raisesTarget: Bool = false, startsUnknown: Bool = false,
        thresholds: FocusDialThresholds = FocusDialThresholds()
    ) {
        self.target = target
        self.raisesTarget = raisesTarget
        greenHalfWidth = 1 - goodShare
        side = startsUnknown ? .unknown : .approaching
        self.thresholds = thresholds
    }

    mutating func update(value: Double, seconds: Double) -> FocusDialReading {
        if raisesTarget, value > (target ?? 0) { target = value }
        guard let target, target > 0 else { return reading(distance: 0, wrongWay: false) }
        startValue = startValue ?? value
        if flipped, value < low {
            low = value
            localMax = value
        } else {
            localMax = max(localMax, value)
        }
        // Armed: a flip needs a local maximum near the target, a fall from it, and (after a
        // flip) a rise of its own above the low before it.
        let armed = !flipped || localMax >= low * (1 + thresholds.passDropShare)
        let dropped = value <= localMax * (1 - thresholds.passDropShare)
        let near = localMax >= thresholds.nearShare * target
        var wrongWay = false
        switch side {
        case .approaching, .past:
            if armed, near, dropped {
                side = side == .past ? .approaching : .past
                localMax = value
                low = value
                flipped = true
            }
        case .unknown:
            let start = startValue ?? value
            if value >= start * (1 + thresholds.passDropShare) {
                side = .approaching
                localMax = value
            } else {
                wrongWay = value <= start * (1 - thresholds.passDropShare)
            }
        }
        return reading(distance: min(max(1 - value / target, 0), 1), wrongWay: wrongWay)
    }

    private func reading(distance: Double, wrongWay: Bool) -> FocusDialReading {
        let green = target != nil && distance <= greenHalfWidth
        // Past is positive; approaching and unknown negative; the far side for a wrong way.
        let offset = side == .past || wrongWay ? distance : -distance
        let almost = max(thresholds.almostBand, greenHalfWidth + 0.10)
        let message: String
        if target == nil {
            message = ""
        } else if wrongWay {
            message = "Wrong way. Turn the other way"
        } else if green {
            message = "Sharp ✓"
        } else if side == .past {
            message = "Too far. Turn back slowly"
        } else if distance <= almost {
            message = "Almost there. Slowly"
        } else {
            message = "Keep turning slowly"
        }
        return FocusDialReading(
            offset: offset, side: side, greenHalfWidth: greenHalfWidth, isGreen: green && !wrongWay,
            isWrongWay: wrongWay, message: message)
    }
}
