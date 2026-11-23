import Foundation

/// The screen's brightness, 0 to 1. A protocol so tests can use a fake screen.
protocol ScreenBrightness: AnyObject {
    var brightness: Double { get set }
}

/// Dims the screen while the phone is hot, and only ever dims it: the person's own level is
/// remembered when the dimming starts, the screen goes to `max(level - drop, minimum)` and never
/// above the level, and the level comes back when the heat mode returns to normal or the scan is
/// left. If the person changes the brightness while it is dimmed, their new value is their level
/// from then on and nothing fights it. Main thread only.
final class BrightnessController {
    private let screen: ScreenBrightness
    private let thresholds: HeatThresholds
    /// The person's level; non-nil exactly while dimmed.
    private var userLevel: Double?
    /// What this controller last put on the screen, to tell its own change from the person's.
    private var applied: Double?

    init(screen: ScreenBrightness, thresholds: HeatThresholds = HeatThresholds()) {
        self.screen = screen
        self.thresholds = thresholds
    }

    var isDimmed: Bool { userLevel != nil }

    /// The heat mode changed: dim for the hot modes, restore for normal.
    func apply(_ mode: HeatMode) {
        if mode == .normal {
            restore()
        } else {
            dim()
        }
    }

    /// The person's own brightness back, if it was dimmed.
    func restore() {
        guard let level = userLevel else { return }
        userLevel = nil
        applied = nil
        if abs(screen.brightness - level) > 0.001 { screen.brightness = level }
    }

    /// The system says the brightness changed. A value other than the one set here is the
    /// person's: it becomes their level, and the screen is left as they set it.
    func screenChanged() {
        guard userLevel != nil, let applied else { return }
        let now = screen.brightness
        if abs(now - applied) > 0.01 {
            userLevel = now
            self.applied = now
        }
    }

    private func dim() {
        guard userLevel == nil else { return }
        let level = screen.brightness
        userLevel = level
        let target = min(max(level - thresholds.coolDownBrightnessDrop, thresholds.minimumBrightness), level)
        applied = target
        if target != level { screen.brightness = target }
    }
}
