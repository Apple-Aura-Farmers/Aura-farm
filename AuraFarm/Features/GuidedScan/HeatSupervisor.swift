import AVFoundation
import UIKit

/// The system's screen, through the scene (`UIScreen.main` is deprecated).
private final class SystemScreen: ScreenBrightness {
    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    var brightness: Double {
        get { Double(screen?.brightness ?? 0.5) }
        set { screen?.brightness = CGFloat(newValue) }
    }
}

/// Everything heat-adaptive mode needs between the thermal state and the screen. The policy runs
/// on the analysis queue, on the frames' own clock; the screen and the idle timer are touched on
/// the main queue only.
final class HeatSupervisor {
    // MARK: Analysis queue

    private var policy = HeatPolicy()
    /// The lab's "Heat-adaptive mode" toggle. Off: the mode stays normal. Analysis queue.
    var isEnabled = true

    /// The mode for this reading; normal while the toggle is off.
    func update(_ state: ProcessInfo.ThermalState, seconds: Double) -> HeatMode {
        let mode = policy.update(state, seconds: seconds)
        return isEnabled ? mode : .normal
    }

    /// Seconds in each mode since the run began, by `HeatMode.csvName`.
    var secondsByMode: [String: Double] {
        Dictionary(uniqueKeysWithValues: policy.secondsByMode.map { ($0.key.csvName, $0.value) })
    }

    func resetTimes() { policy.resetTimes() }

    // MARK: Main queue

    private let brightness = BrightnessController(screen: SystemScreen())
    private var mode = HeatMode.normal
    private var observers: [NSObjectProtocol] = []
    private let lock = NSLock()
    private var level: Double?

    /// The screen's brightness as last seen on the main queue; for the CSV.
    var screenBrightness: Double? {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    /// The scan starts: the screen stays awake if asked, and the ways out are watched.
    func begin(keepsScreenAwake: Bool) {
        guard observers.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = keepsScreenAwake
        record()
        let center = NotificationCenter.default
        func watch(_ name: Notification.Name, _ body: @escaping () -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in body() })
        }
        watch(UIScreen.brightnessDidChangeNotification) { [weak self] in
            self?.brightness.screenChanged()
            self?.record()
        }
        // Leaving the app or losing the camera gives the person's brightness back at once.
        watch(UIApplication.willResignActiveNotification) { [weak self] in self?.restore() }
        watch(AVCaptureSession.didStopRunningNotification) { [weak self] in self?.restore() }
        watch(UIApplication.didBecomeActiveNotification) { [weak self] in
            guard let self else { return }
            self.brightness.apply(self.mode)
            self.record()
        }
    }

    /// The heat mode changed.
    func apply(_ newMode: HeatMode) {
        mode = newMode
        brightness.apply(newMode)
        record()
    }

    /// The scan is left, in any way: brightness back, the screen may sleep again.
    func end() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        mode = .normal
        restore()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func restore() {
        brightness.restore()
        record()
    }

    private func record() {
        lock.lock()
        level = Double(
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first?
                .brightness ?? 0)
        lock.unlock()
    }
}
