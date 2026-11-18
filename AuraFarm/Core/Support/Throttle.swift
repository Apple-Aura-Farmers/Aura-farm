import Foundation

/// The numbers the lab's screen updates are paced with. Data, not logic.
struct ScreenUpdateThresholds {
    /// Panels, the mini-map and the count update at most this many times a second, with the
    /// latest value always arriving last. PLACEHOLDER: 4 a second is easy to read and a quarter of
    /// the analysis rate; nothing the helper steers by (the guide overlay, haptics) is paced.
    var updatesPerSecond = 4.0

    var interval: Double { 1 / max(updatesPerSecond, 0.1) }
}

/// Leading and trailing throttle, as pure timing logic: the first value goes at once, values
/// offered within `interval` of the last send wait (only the newest is kept), and the newest
/// pending value goes once `interval` has passed. Time is passed in, so it is tested without a
/// clock.
struct Throttle<Value> {
    var interval: Double
    private var lastSentAt: Double?
    private(set) var pending: Value?

    init(interval: Double = ScreenUpdateThresholds().interval) {
        self.interval = interval
    }

    /// The value to send now, or nil when it must wait (it is kept as the pending one).
    /// - Parameter force: send at once, for a change that must not wait (a step of the setup).
    mutating func offer(_ value: Value, at now: Double, force: Bool = false) -> Value? {
        if force || isDue(at: now) {
            lastSentAt = now
            pending = nil
            return value
        }
        pending = value
        return nil
    }

    /// The pending value, once it is due (the trailing send); nil while it must wait or when
    /// there is none.
    mutating func takePending(at now: Double) -> Value? {
        guard let value = pending, isDue(at: now) else { return nil }
        lastSentAt = now
        pending = nil
        return value
    }

    /// The pending value now, due or not (the analysis is stopping).
    mutating func flush() -> Value? {
        defer { pending = nil }
        return pending
    }

    /// How long until a pending value may go; nil when nothing is pending.
    func secondsUntilDue(at now: Double) -> Double? {
        guard pending != nil, let lastSentAt else { return pending == nil ? nil : 0 }
        return max(lastSentAt + interval - now, 0)
    }

    private func isDue(at now: Double) -> Bool {
        guard let lastSentAt else { return true }
        return now - lastSentAt >= interval - 1e-9
    }
}

/// A `Throttle` that delivers on the main queue. `offer` may be called from any queue (the
/// analysis queue); `apply` always runs on main. A value that had to wait is delivered by a
/// trailing timer, so the screen always ends on the latest value.
final class MainThrottle<Value> {
    private var throttle: Throttle<Value>
    /// Where values go, on the main queue. Set once, after the owner exists.
    var apply: (Value) -> Void
    private let lock = NSLock()
    private var isTimerSet = false

    init(
        interval: Double = ScreenUpdateThresholds().interval,
        apply: @escaping (Value) -> Void = { _ in }
    ) {
        throttle = Throttle(interval: interval)
        self.apply = apply
    }

    func offer(_ value: Value, force: Bool = false) {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let send = throttle.offer(value, at: now, force: force)
        var wait: Double?
        if send == nil, !isTimerSet {
            isTimerSet = true
            wait = throttle.secondsUntilDue(at: now)
        }
        lock.unlock()
        if let send { DispatchQueue.main.async { self.apply(send) } }
        if let wait { schedule(after: wait) }
    }

    /// Delivers the pending value now (the analysis is stopping).
    func flush() {
        lock.lock()
        let value = throttle.flush()
        lock.unlock()
        if let value { DispatchQueue.main.async { self.apply(value) } }
    }

    private func schedule(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let now = ProcessInfo.processInfo.systemUptime
            let value = self.throttle.takePending(at: now)
            let next = value == nil ? self.throttle.secondsUntilDue(at: now) : nil
            self.isTimerSet = next != nil
            self.lock.unlock()
            if let value { self.apply(value) }
            if let next { self.schedule(after: next) }
        }
    }
}
