import Foundation
import UIKit

/// What the phone itself is doing while the lab runs, for the CSV and a badge: its thermal state
/// and battery level. Battery monitoring is on only while the lab is open.
final class LabDeviceStatus {
    private let lock = NSLock()
    private var level: Double?
    private var observer: NSObjectProtocol?

    /// Main queue.
    func begin() {
        guard observer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        store(UIDevice.current.batteryLevel)
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.store(UIDevice.current.batteryLevel) }
    }

    /// Main queue.
    func end() {
        UIDevice.current.isBatteryMonitoringEnabled = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// 0 to 1; nil when the phone does not say (the simulator reports -1).
    var batteryLevel: Double? {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    private func store(_ value: Float) {
        lock.lock()
        level = value >= 0 ? Double(value) : nil
        lock.unlock()
    }

    static func name(of state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static var thermalName: String { name(of: ProcessInfo.processInfo.thermalState) }
}
