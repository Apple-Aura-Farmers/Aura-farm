import Foundation

enum StageLimitEnd: Equatable {
    case min, max
}

/// The angles each servo may reach, as the board reports them (its flash may hold narrower
/// ones than 0...180).
struct StageLimits: Equatable {
    var xMin = 0
    var xMax = 180
    var yMin = 0
    var yMax = 180

    func range(of axis: StageAxis) -> ClosedRange<Int> {
        axis == .x ? xMin...xMax : yMin...yMax
    }

    func clamp(_ angle: Int, _ axis: StageAxis) -> Int {
        let r = range(of: axis)
        return min(max(angle, r.lowerBound), r.upperBound)
    }

    func isAtEnd(_ axis: StageAxis, _ angle: Int) -> StageLimitEnd? {
        let r = range(of: axis)
        if angle <= r.lowerBound { return .min }
        if angle >= r.upperBound { return .max }
        return nil
    }

    /// Whether `min` and `max` can be a servo's range.
    static func isSane(_ min: Int, _ max: Int) -> Bool {
        min < max && min >= 0 && max <= 180
    }

    /// Takes the range out of a refusal such as "LIMIT 10-170"; anything else changes nothing.
    mutating func merge(refusal text: String, axis: StageAxis) {
        let parts = text.split(separator: " ")
        guard parts.count == 2, parts[0] == "LIMIT" else { return }
        let bounds = parts[1].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let low = Int(bounds[0]), let high = Int(bounds[1]),
            Self.isSane(low, high)
        else { return }
        if axis == .x { (xMin, xMax) = (low, high) } else { (yMin, yMax) = (low, high) }
    }
}
