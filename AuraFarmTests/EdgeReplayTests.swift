import XCTest

@testable import AuraFarm

/// Phase 2u part A: the replay of the 17 Nov 2026 21:38 and 22:12 full-cover runs through the line
/// rule, and the synthetic cases of the second (empty area ahead) way to accept an edge line.
final class EdgeReplayTests: XCTestCase {
    private let fixtures = ["edge-run-2138", "edge-run-2212", "edge-run-2258"]
    private let strongShares = [0.10, 0.15, 0.20]

    private func thresholds(strong: Double) -> LineEdgeThresholds {
        var thresholds = LineEdgeThresholds()
        thresholds.strongAreaShare = strong
        return thresholds
    }

    /// Prints the table of the report: the Phase 2u rule against each `strongAreaShare`.
    func testReplayTableForTheThreeRuns() throws {
        for name in fixtures {
            let legs = try EdgeReplay.legs(named: name, in: Bundle(for: Self.self))
            print("REPLAY \(name) legs \(legs.count)")
            let strict = EdgeReplay.run(legs, thresholds: EdgeReplay.strictRule)
            let today = EdgeReplay.run(legs, thresholds: EdgeReplay.todaysRule)
            print("REPLAY   strict ", EdgeReplay.table(strict))
            print("REPLAY   today  ", EdgeReplay.table(today))
            for share in strongShares {
                let outcome = EdgeReplay.run(legs, thresholds: thresholds(strong: share))
                print("REPLAY   strong \(share)", EdgeReplay.table(outcome))
            }
        }
    }

    /// Phase 2u: the area rule confirms more bottom ends than the strict rule alone, with no more
    /// false confirmations, on the first two runs.
    func testTheAreaRuleConfirmsMoreBottomEndsThanTheStrictRule() throws {
        for name in fixtures.prefix(2) {
            let legs = try EdgeReplay.legs(named: name, in: Bundle(for: Self.self))
            XCTAssertGreaterThanOrEqual(legs.count, 10, name)
            let strict = EdgeReplay.run(legs, thresholds: EdgeReplay.strictRule)
            let area = EdgeReplay.run(legs, thresholds: EdgeReplay.todaysRule)
            XCTAssertGreaterThanOrEqual(area.confirmedLegs, strict.confirmedLegs, name)
            XCTAssertGreaterThan(area.confirmedBottomLegs, strict.confirmedBottomLegs, name)
            XCTAssertLessThanOrEqual(area.falseConfirmations, strict.falseConfirmations, name)
        }
    }

    /// Phase 3a: the strong-line rule on all three runs loses no edge confirmed today and adds no
    /// false confirmation, and it confirms run C's column 5 bottom edge.
    func testTheStrongLineRuleLosesNoEdgeAndAddsNoFalseOne() throws {
        for name in fixtures {
            let legs = try EdgeReplay.legs(named: name, in: Bundle(for: Self.self))
            let today = EdgeReplay.run(legs, thresholds: EdgeReplay.todaysRule)
            let chosen = EdgeReplay.run(legs, thresholds: LineEdgeThresholds())
            XCTAssertGreaterThanOrEqual(chosen.confirmedLegs, today.confirmedLegs, name)
            for (before, after) in zip(today.legs, chosen.legs) where before.confirmed {
                XCTAssertTrue(after.confirmed, "\(name) \(after.name) lost")
            }
            XCTAssertLessThanOrEqual(chosen.falseConfirmations, today.falseConfirmations, name)
        }
        let runC = try EdgeReplay.legs(named: "edge-run-2258", in: Bundle(for: Self.self))
        let today = EdgeReplay.run(runC, thresholds: EdgeReplay.todaysRule)
        let chosen = EdgeReplay.run(runC, thresholds: LineEdgeThresholds())
        let column5 = { (outcome: EdgeReplay.Outcome) in
            outcome.legs.first { $0.name == "column 5 down" }
        }
        XCTAssertEqual(column5(today)?.confirmed, false)
        XCTAssertEqual(column5(chosen)?.confirmed, true)
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

    /// A strong straight line with an empty area ahead, whatever beyond/before is.
    private func strongLine(area: Double?, angle: Double = 4, beyond: Double = 90) -> LineAccept? {
        var tracker = LineEdgeTracker(confirmSeconds: 1.0)
        let quarter = area.map { $0 * 50 }
        var seconds = 0.0
        func reading(offset: Double, still: Double) -> GuideReading {
            seconds += 0.1
            return GuideReading(
                seconds: seconds, position: .zero, tracking: .tracking, unconfirmedGaps: 0,
                viewClass: .sample, speedFraction: 0.05, isStill: still > 0, quadAheadAway: quarter,
                quadAheadToward: quarter, quadBehindAway: quarter == nil ? nil : 50,
                quadBehindToward: quarter == nil ? nil : 50, stillSeconds: still,
                edgeLine: EdgeLine(
                    strength: 20, coverage: 1, longestRun: 8, angleDegrees: angle, offsetFields: offset,
                    sign: 1, slideResidualFields: 0.05, path: [], isCandidate: true,
                    beforeEnergy: 100, beyondEnergy: beyond))
        }
        for index in 0..<10 { tracker.update(reading(offset: 1.0 - Double(index) * 0.1, still: 0)) }
        for index in 1...30 {
            tracker.update(reading(offset: 0.05, still: Double(index) * 0.1))
            if tracker.state == .confirmed { return tracker.accept }
        }
        return nil
    }

    func testAStrongStraightLineWithAnEmptyAreaIsAcceptedWhateverBeyondOverBeforeIs() {
        XCTAssertEqual(strongLine(area: 0.05), .strongArea)
    }

    func testTheSameLineWithAreaAhead04IsNotAccepted() {
        XCTAssertNil(strongLine(area: 0.4))
    }

    func testTheSameLineAt30DegreesIsNotAccepted() {
        XCTAssertNil(strongLine(area: 0.05, angle: 30))
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

    /// Phase 3a: beyond above 0.6 of before is only accepted by the strong-line rule, and only
    /// with the area clearly empty.
    func testBeyondAbove06OfBeforeIsOnlyAcceptedByTheStrongLineRuleWithAClearlyEmptyArea() {
        XCTAssertEqual(confirms(beyond: 70, area: 0.02), .strongArea)
        XCTAssertNil(confirms(beyond: 70, area: 0.25))
    }
}
