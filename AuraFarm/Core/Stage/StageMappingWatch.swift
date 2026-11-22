import CoreGraphics
import Foundation

/// What the watch asks the driver to do with a servo's mapping vector.
enum StageMappingCorrection: Equatable {
    /// The picture moved the other way: use `vector` (fields per degree) instead.
    case flip(servo: StageAxis, vector: CGPoint)
    /// The step size is off by a lot: use `vector`, blended part of the way to the measurement.
    case scale(servo: StageAxis, vector: CGPoint)
}

/// Checks the mapping against what the picture really did, move by move, so a servo whose sign
/// (or step size) was measured wrong is corrected while the stage runs. Pure.
struct StageMappingWatch {
    private struct Move {
        var degrees: Double
        var delta: CGPoint
    }

    var keepMoves = 8
    /// A move counts as going against the mapping only when the picture moved at least this far.
    var minObservedFields = 0.05
    var againstMovesToFlip = 3
    var fitMovesToFlip = 4
    var fitMovesToScale = 6
    /// A fitted vector shorter than this share of the current one is too weak to trust.
    var minFitShare = 0.3
    var scaleRatio = 1.5

    private var moves: [StageAxis: [Move]] = [:]

    mutating func reset(_ servo: StageAxis? = nil) {
        if let servo { moves[servo] = [] } else { moves = [:] }
    }

    /// - Parameters:
    ///   - degrees: how far the servo turned.
    ///   - delta: how far the picture moved meanwhile, in raw guide fields.
    ///   - trackingLost: tracking was lost between the two positions: the move is ignored.
    mutating func record(
        servo: StageAxis, degrees: Double, delta: CGPoint, trackingLost: Bool = false,
        mapping: StageServoMapping
    ) -> StageMappingCorrection? {
        guard !trackingLost, degrees != 0 else { return nil }
        var list = moves[servo, default: []]
        list.append(Move(degrees: degrees, delta: delta))
        if list.count > keepMoves { list.removeFirst(list.count - keepMoves) }
        moves[servo] = list

        let current = servo == .x ? mapping.x : mapping.y
        let currentLength = hypot(Double(current.x), Double(current.y))
        guard currentLength > 0 else { return nil }
        let fit = Self.fit(list)

        // (a) The last few moves all went against the mapping.
        let recent = list.suffix(againstMovesToFlip)
        let allAgainst =
            recent.count == againstMovesToFlip
            && recent.allSatisfy { move in
                hypot(Double(move.delta.x), Double(move.delta.y)) >= minObservedFields
                    && Self.dot(move.delta, current) * move.degrees < 0
            }
        // (b) The fit over enough moves points the other way.
        let fitAgainst =
            list.count >= fitMovesToFlip
            && fit.map { Self.dot($0, current) < 0 && Self.length($0) >= minFitShare * currentLength }
                == true
        if allAgainst || fitAgainst {
            moves[servo] = []
            if let fit, Self.dot(fit, current) < 0, Self.length(fit) >= minFitShare * currentLength {
                return .flip(servo: servo, vector: fit)
            }
            return .flip(servo: servo, vector: CGPoint(x: -current.x, y: -current.y))
        }

        // Same direction, but the step size is far off: blend the length halfway to the fit.
        if list.count >= fitMovesToScale, let fit, Self.dot(fit, current) > 0 {
            let ratio = Self.length(fit) / currentLength
            if ratio > scaleRatio || ratio < 1 / scaleRatio {
                let blended = 0.5 * currentLength + 0.5 * Self.length(fit)
                let factor = blended / currentLength
                moves[servo] = []
                return .scale(
                    servo: servo,
                    vector: CGPoint(x: Double(current.x) * factor, y: Double(current.y) * factor))
            }
        }
        return nil
    }

    /// Fields per degree: sum of delta x degrees over the sum of degrees squared.
    private static func fit(_ list: [Move]) -> CGPoint? {
        let denominator = list.reduce(0) { $0 + $1.degrees * $1.degrees }
        guard denominator > 0 else { return nil }
        let x = list.reduce(0) { $0 + Double($1.delta.x) * $1.degrees } / denominator
        let y = list.reduce(0) { $0 + Double($1.delta.y) * $1.degrees } / denominator
        return CGPoint(x: x, y: y)
    }

    private static func dot(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(a.x * b.x + a.y * b.y)
    }

    private static func length(_ v: CGPoint) -> Double { hypot(Double(v.x), Double(v.y)) }
}
