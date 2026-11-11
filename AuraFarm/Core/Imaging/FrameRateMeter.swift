import Foundation

/// Analyzed frames per second over the last second, from the frames' own timestamps.
struct FrameRateMeter {
    /// How far back the rate looks, in seconds.
    static let windowSeconds = 1.0

    private var times: [Double] = []

    /// Records a frame and returns the rate: 0 until two frames fall inside the window.
    mutating func record(_ seconds: Double) -> Double {
        times.append(seconds)
        times.removeAll { seconds - $0 > Self.windowSeconds }
        guard times.count >= 2, let first = times.first, seconds > first else { return 0 }
        return Double(times.count - 1) / (seconds - first)
    }

    mutating func reset() {
        times = []
    }
}
