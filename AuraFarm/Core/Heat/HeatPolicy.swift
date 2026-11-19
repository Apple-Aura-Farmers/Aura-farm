import Foundation

/// How much work the phone does for the scan, from its heat. Ordered: later is hotter.
enum HeatMode: Int, Comparable, CaseIterable {
    case normal, coolDown, tooHot

    static func < (lhs: HeatMode, rhs: HeatMode) -> Bool { lhs.rawValue < rhs.rawValue }

    /// A short word for the CSV and the run record.
    var csvName: String {
        switch self {
        case .normal: "normal"
        case .coolDown: "cool_down"
        case .tooHot: "too_hot"
        }
    }
}

/// The numbers the heat mode works with. Data, not logic. All PLACEHOLDER; source: an iPhone 17
/// reaches "serious" after about 8 minutes of guided scan, and iOS then slows tracking too.
struct HeatThresholds {
    /// A hotter mode is taken at once; a cooler one only after the thermal state has stayed at
    /// the cooler level this long, and then one level at a time.
    var stepDownSeconds = 30.0
    /// In `coolDown` the model runs at most this often a second.
    var coolDownModelMaxPerSecond = 3.0
    /// In `coolDown` the edge-line probe runs on every Nth frame (2 when normal).
    var coolDownEdgeProbeEveryNthFrame = 4
    /// In `coolDown` and `tooHot` the screen goes this far below the person's own level...
    var coolDownBrightnessDrop = 0.15
    /// ...but not under this, and never above the person's level.
    var minimumBrightness = 0.2
}

/// Turns the phone's thermal state into a heat mode, with hysteresis. Pure; the readings' own
/// clock comes in with each reading.
struct HeatPolicy {
    var thresholds = HeatThresholds()
    private(set) var mode = HeatMode.normal
    /// Seconds spent in each mode since the last `resetTimes()`.
    private(set) var secondsByMode: [HeatMode: Double] = [:]
    private var coolerSince: Double?
    private var lastSeconds: Double?

    /// nominal and fair: normal. serious: cool down. critical: too hot.
    static func target(for state: ProcessInfo.ThermalState) -> HeatMode {
        switch state {
        case .serious: .coolDown
        case .critical: .tooHot
        default: .normal
        }
    }

    /// The mode after this reading.
    @discardableResult
    mutating func update(_ state: ProcessInfo.ThermalState, seconds: Double) -> HeatMode {
        if let lastSeconds {
            // A long gap (the camera stopped) does not count as time in a mode.
            secondsByMode[mode, default: 0] += min(max(seconds - lastSeconds, 0), 1)
        }
        lastSeconds = seconds
        let wanted = Self.target(for: state)
        if wanted >= mode {
            mode = wanted
            coolerSince = nil
        } else {
            let since = coolerSince ?? seconds
            coolerSince = since
            if seconds - since >= thresholds.stepDownSeconds - 1e-9 {
                mode = HeatMode(rawValue: mode.rawValue - 1) ?? .normal
                // Still cooler than the new mode: the next level needs its own 30 s.
                coolerSince = wanted < mode ? seconds : nil
            }
        }
        return mode
    }

    mutating func resetTimes() {
        secondsByMode = [:]
    }
}
