import CoreGraphics
import Foundation

/// Big, glanceable feedback for moving a slide by hand: am I tracking, am I too fast, how
/// close is the next hop, how far from the start, am I still. Fed one analyzed frame at a time.
///
/// Speed is read from the frame-to-frame shake reading, which is the registration's answer and
/// not the true knob speed: a reading that failed counts as no movement, and a move too fast to
/// register shows up as lost rather than as a high speed.
struct MovementIndicators {
    enum Status: Equatable { case starting, tracking, tooFast, lost }
    enum SpeedZone: Equatable { case comfortable, fast, tooFast }

    var thresholds: MovementIndicatorThresholds

    private(set) var status = Status.starting
    /// Frame-to-frame movement as a share of the short side, averaged over `speedWindow`.
    private(set) var speedFraction = 0.0
    private(set) var speedZone = SpeedZone.comfortable
    /// 0...1: the live offset from the anchor against a hop. 0 right after a hop.
    private(set) var hopProgress = 0.0
    /// How long the frame-to-frame movement has stayed under `stillPixels`, in seconds.
    private(set) var stillSeconds = 0.0
    /// Where Mark start was pressed, in frames.
    private(set) var startPosition: CGPoint?

    private var speeds: [Double] = []
    private var hasShake = false
    private var latestPosition = CGPoint.zero
    private var lastSeconds: Double?

    init(thresholds: MovementIndicatorThresholds = MovementIndicatorThresholds()) {
        self.thresholds = thresholds
    }

    /// Distance from the marked start, in frames, to the latest position.
    var offStartFrames: Double? {
        guard let startPosition else { return nil }
        return hypot(latestPosition.x - startPosition.x, latestPosition.y - startPosition.y)
    }

    var isHome: Bool {
        guard let off = offStartFrames else { return false }
        return off <= thresholds.homeZoneFrames
    }

    /// - Parameters:
    ///   - shake: frame-to-frame shift in px, nil when registration gave nothing.
    ///   - anchorOffset: the live offset from the anchor in px.
    ///   - seconds: the frame's time; the stillness timer grows by the gap between calls.
    ///   - hopFraction: the odometer's hop threshold, as a share of the short side.
    mutating func update(
        shake: CGPoint?, anchorOffset: CGPoint?, positionFrames: CGPoint, isLost: Bool,
        event: HopOdometer.Event, frameSize: CGSize, seconds: Double, hopFraction: Double
    ) {
        let shortSide = Double(min(frameSize.width, frameSize.height))
        latestPosition = positionFrames

        if shake != nil { hasShake = true }
        let speed = shake.map { hypot(Double($0.x), Double($0.y)) / max(shortSide, 1) } ?? 0
        speeds.append(speed)
        if speeds.count > max(thresholds.speedWindow, 1) {
            speeds.removeFirst(speeds.count - max(thresholds.speedWindow, 1))
        }
        speedFraction = speeds.reduce(0, +) / Double(speeds.count)
        if speedFraction < thresholds.comfortableSpeedFraction {
            speedZone = .comfortable
        } else if speedFraction < thresholds.tooFastSpeedFraction {
            speedZone = .fast
        } else {
            speedZone = .tooFast
        }

        if isLost {
            status = .lost
        } else if !hasShake {
            status = .starting
        } else if speedZone == .tooFast {
            status = .tooFast
        } else {
            status = .tracking
        }

        if let anchorOffset, event != .hop, shortSide > 0, hopFraction > 0 {
            let length = hypot(Double(anchorOffset.x), Double(anchorOffset.y))
            hopProgress = min(max(length / (hopFraction * shortSide), 0), 1)
        } else {
            hopProgress = 0
        }

        // Stillness needs a reading: no shake measurement is not evidence of being still.
        let elapsed = lastSeconds.map { max(seconds - $0, 0) } ?? 0
        lastSeconds = seconds
        if let shake, hypot(Double(shake.x), Double(shake.y)) < thresholds.stillPixels {
            stillSeconds += elapsed
        } else {
            stillSeconds = 0
        }
    }

    mutating func markStart(at positionFrames: CGPoint) {
        startPosition = positionFrames
    }

    mutating func clearStart() {
        startPosition = nil
    }

    mutating func reset() {
        self = MovementIndicators(thresholds: thresholds)
    }
}

extension MovementIndicators.Status {
    /// The word written in the CSV.
    var csvName: String {
        switch self {
        case .starting: "starting"
        case .tracking: "tracking"
        case .tooFast: "too_fast"
        case .lost: "lost"
        }
    }
}
