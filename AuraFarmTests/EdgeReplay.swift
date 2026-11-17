import CoreGraphics
import XCTest

@testable import AuraFarm

/// Test-only: replays a trimmed run CSV (`Fixtures/edge-run-*.csv`) through `LineEdgeTracker`, leg
/// by leg, with reconstructed `EdgeLine` values, and reports where the line was accepted.
///
/// Each column leg starts a fresh tracker (the route resets it between legs) and ends where the
/// run's leg ended: by the helper's ✓ or "Mark edge", at the edge. A leg's `x` axis is the CSV's
/// `position_x_fields`, which is the leg axis in the tracker's frame axes; the line offsets are
/// already along the heading.
struct EdgeReplay {
    struct Leg {
        var name: String
        var readings: [GuideReading]
        /// The position along the leg for each reading (the CSV's `position_x_fields`).
        var along: [Double]
        var endAlong: Double { along.last ?? 0 }
        /// A down leg ends on the bottom edge, an up leg on the top one.
        var isBottom: Bool { name.hasSuffix("down") }
    }

    struct LegOutcome: Equatable {
        var name: String
        var isBottom: Bool
        /// Reached "attached", at the cross, and "confirmed" within 0.6 field of where the leg ended.
        var attached = false
        var atCross = false
        var confirmed = false
    }

    struct Outcome {
        var legs: [LegOutcome]
        /// Confirmations more than 1.5 fields from every leg end.
        var falseConfirmations: Int
        var confirmedLegs: Int { legs.filter(\.confirmed).count }
        var confirmedBottomLegs: Int { legs.filter { $0.confirmed && $0.isBottom }.count }
        var attachedLegs: Int { legs.filter(\.attached).count }
    }

    /// The helper's ✓ came about a second into the rest, so the replay confirms after 1 s, not the
    /// route's 2 s.
    static let confirmSeconds = 1.0

    /// The column legs of a fixture, in order.
    static func legs(named name: String, in bundle: Bundle) throws -> [Leg] {
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "csv"), "missing \(name)")
        let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
        let header = try XCTUnwrap(lines.first).split(separator: ",", omittingEmptySubsequences: false)
        let index = Dictionary(
            header.enumerated().map { (String($1), $0) }, uniquingKeysWith: { first, _ in first })
        var legs: [Leg] = []
        var current: Leg?
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            func text(_ key: String) -> String { index[key].map { fields[$0] } ?? "" }
            func number(_ key: String) -> Double? { Double(text(key)) }
            let state = text("guide_state")
            guard state.hasPrefix("column"), state.hasSuffix("up") || state.hasSuffix("down"),
                let x = number("position_x_fields"), let y = number("position_y_fields")
            else {
                if let finished = current { legs.append(finished) }
                current = nil
                continue
            }
            if let open = current, open.name != state {
                legs.append(open)
                current = nil
            }
            var line: EdgeLine?
            if let strength = number("edge_line_strength"), let offset = number("edge_line_offset_fields") {
                line = EdgeLine(
                    strength: strength, coverage: number("edge_line_coverage") ?? 0,
                    longestRun: Int(number("edge_line_longest_run") ?? 0),
                    angleDegrees: number("edge_line_angle_deg") ?? 0, offsetFields: offset,
                    sign: Int(number("edge_line_sign") ?? 0),
                    slideResidualFields: number("edge_line_slide_residual"), path: [],
                    isCandidate: text("edge_line_candidate") == "1",
                    beforeEnergy: number("line_before_energy"), beyondEnergy: number("line_beyond_energy"))
            }
            let still = number("still_seconds") ?? 0
            let reading = GuideReading(
                seconds: number("seconds") ?? 0, position: CGPoint(x: y, y: -x), tracking: .tracking,
                unconfirmedGaps: 0, viewClass: ViewClass(rawValue: text("view_class")) ?? .sample,
                speedFraction: number("speed_fraction") ?? 0, isStill: still > 0,
                quadAheadAway: number("quad_ahead_away"), quadAheadToward: number("quad_ahead_toward"),
                quadBehindAway: number("quad_behind_away"),
                quadBehindToward: number("quad_behind_toward"), stillSeconds: still, edgeLine: line)
            var leg = current ?? Leg(name: state, readings: [], along: [])
            leg.readings.append(reading)
            leg.along.append(x)
            current = leg
        }
        if let finished = current { legs.append(finished) }
        return legs
    }

    static func run(_ legs: [Leg], thresholds: LineEdgeThresholds) -> Outcome {
        let ends = legs.map(\.endAlong)
        var outcomes: [LegOutcome] = []
        var falseCount = 0
        for leg in legs {
            var tracker = LineEdgeTracker(thresholds: thresholds, confirmSeconds: confirmSeconds)
            var outcome = LegOutcome(name: leg.name, isBottom: leg.isBottom)
            for (reading, x) in zip(leg.readings, leg.along) {
                tracker.update(reading)
                let near = abs(x - leg.endAlong) <= 0.6
                if near, tracker.state == .attached || tracker.event == "line_confirmed" {
                    outcome.attached = true
                }
                if near, tracker.atCross { outcome.atCross = true }
                if tracker.event == "line_confirmed" {
                    if near {
                        outcome.confirmed = true
                    } else if ends.allSatisfy({ abs(x - $0) > 1.5 }) {
                        falseCount += 1
                    }
                    tracker.consume()
                }
            }
            outcomes.append(outcome)
        }
        return Outcome(legs: outcomes, falseConfirmations: falseCount)
    }

    /// The rule as it was before Phase 2u: only the strict beyond/before share.
    static var strictRule: LineEdgeThresholds {
        var thresholds = LineEdgeThresholds()
        thresholds.maxAreaAheadShare = -1
        thresholds.strongAreaShare = -1
        return thresholds
    }

    /// The rule as it was after Phase 2u: strict, or the empty area ahead; no strong-line rule.
    static var todaysRule: LineEdgeThresholds {
        var thresholds = LineEdgeThresholds()
        thresholds.strongAreaShare = -1
        return thresholds
    }

    /// One line per leg and a total, for the report: `A` attached, `C` at the cross, `X` confirmed.
    static func table(_ outcome: Outcome) -> String {
        let cells = outcome.legs.map {
            "\($0.isBottom ? "B" : "T")\($0.attached ? "A" : "-")\($0.atCross ? "C" : "-")"
                + "\($0.confirmed ? "X" : "-")"
        }
        return cells.joined(separator: " ")
            + " | attached \(outcome.attachedLegs) confirmed \(outcome.confirmedLegs)"
            + " (bottom \(outcome.confirmedBottomLegs)) false \(outcome.falseConfirmations)"
    }
}
