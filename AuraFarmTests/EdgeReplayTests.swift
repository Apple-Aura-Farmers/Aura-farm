import XCTest

@testable import AuraFarm

/// Phase 2u part A: the replay of the 17 Nov 2026 21:38 and 22:12 full-cover runs through the line
/// rule, and the synthetic cases of the second (empty area ahead) way to accept an edge line.
final class EdgeReplayTests: XCTestCase {
    private let fixtures = ["edge-run-2138", "edge-run-2212"]
    private let shares = [0.2, 0.3, 0.5]

    private func thresholds(share: Double) -> LineEdgeThresholds {
        var thresholds = LineEdgeThresholds()
        thresholds.maxAreaAheadShare = share
        return thresholds
    }

    /// Prints the table of the report: today's rule against each `maxAreaAheadShare`.
    func testReplayTableForBothRuns() throws {
        for name in fixtures {
            let legs = try EdgeReplay.legs(named: name, in: Bundle(for: Self.self))
            print("REPLAY \(name) legs \(legs.count)")
            let today = EdgeReplay.run(legs, thresholds: EdgeReplay.todaysRule)
            print("REPLAY   today  ", EdgeReplay.table(today))
            for share in shares {
                let outcome = EdgeReplay.run(legs, thresholds: thresholds(share: share))
                print("REPLAY   \(share)", EdgeReplay.table(outcome))
            }
        }
    }

    /// The default (chosen) rule confirms at least as many leg ends as today and more bottom ends,
    /// with no more false confirmations, on both runs.
    func testTheChosenRuleConfirmsMoreBottomEndsWithNoMoreFalseOnes() throws {
        for name in fixtures {
            let legs = try EdgeReplay.legs(named: name, in: Bundle(for: Self.self))
            XCTAssertGreaterThanOrEqual(legs.count, 10, name)
            let today = EdgeReplay.run(legs, thresholds: EdgeReplay.todaysRule)
            let chosen = EdgeReplay.run(legs, thresholds: LineEdgeThresholds())
            XCTAssertGreaterThanOrEqual(chosen.confirmedLegs, today.confirmedLegs, name)
            XCTAssertGreaterThan(chosen.confirmedBottomLegs, today.confirmedBottomLegs, name)
            XCTAssertLessThanOrEqual(chosen.falseConfirmations, today.falseConfirmations, name)
        }
    }

    // MARK: Synthetic

    private func line(
        _ offset: Double, before: Double = 100, beyond: Double, angle: Double = 0
    ) -> EdgeLine {
        EdgeLine(
            strength: 12, coverage: 1, longestRun: 8, angleDegrees: angle, offsetFields: offset,
            sign: 1, slideResidualFields: 0.05, path: [], isCandidate: true, beforeEnergy: before,
            beyondEnergy: beyond)
    }

    /// The line comes to the cross with the helper moving, then rests on it for 3 s; `area` is the
    /// detail ahead over behind on every reading.
    private func confirms(beyond: Double, area: Double?, angle: Double = 0) -> LineAccept? {
        var tracker = LineEdgeTracker(confirmSeconds: 1.0)
        let quarter = area.map { $0 * 50 }
        func reading(_ seconds: Double, offset: Double, still: Double) -> GuideReading {
            GuideReading(
                seconds: seconds, position: .zero, tracking: .tracking, unconfirmedGaps: 0,
                viewClass: .sample, speedFraction: 0.05, isStill: still > 0,
                quadAheadAway: quarter, quadAheadToward: quarter, quadBehindAway: quarter == nil ? nil : 50,
                quadBehindToward: quarter == nil ? nil : 50, stillSeconds: still,
                edgeLine: line(offset, beyond: beyond, angle: angle))
        }
        var seconds = 0.0
        for index in 0..<10 {
            seconds += 0.1
            tracker.update(reading(seconds, offset: 1.0 - Double(index) * 0.1, still: 0))
        }
        for index in 1...30 {
            seconds += 0.1
            tracker.update(reading(seconds, offset: 0.05, still: Double(index) * 0.1))
            if tracker.state == .confirmed { return tracker.accept }
        }
        return nil
    }

    func testABottomEdgeWithBeyondOverBefore045AndAreaAhead005IsAcceptedByTheAreaRule() {
        XCTAssertEqual(confirms(beyond: 45, area: 0.05), .area)
    }

    func testTheStrictRuleStillAcceptsAnEmptyBeyondWithoutTheArea() {
        XCTAssertEqual(confirms(beyond: 10, area: nil), .strict)
    }

    func testASampleInteriorLineWithAreaAhead08IsNotAccepted() {
        XCTAssertNil(confirms(beyond: 45, area: 0.8))
    }

    func testAnUnknownAreaCannotPassTheAreaRule() {
        XCTAssertNil(confirms(beyond: 45, area: nil))
    }

    func testAnAngledLineAt40DegreesIsNotAcceptedByTheAreaRule() {
        XCTAssertNil(confirms(beyond: 45, area: 0.05, angle: 40))
        XCTAssertEqual(confirms(beyond: 45, area: 0.05, angle: 15), .area)
    }

    func testBeyondAbove06OfBeforeIsNotAcceptedEvenWithAnEmptyArea() {
        XCTAssertNil(confirms(beyond: 70, area: 0.02))
    }
}
