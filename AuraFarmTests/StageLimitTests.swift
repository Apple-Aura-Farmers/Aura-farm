import XCTest

@testable import AuraFarm

/// Phase 2h part C: the helper says the stage cannot go further, and the limit is remembered.
final class StageLimitTests: XCTestCase {
    private let route = ScriptedRoute()

    /// Column 1 up for `spots` more spots, then the limit pressed where the view is.
    private func climb(spots: Int) {
        route.startColumnOne()
        for _ in 0..<spots { route.visitTarget() }
    }

    func testALimitOnAnUpLegTurnsTheColumnDown() throws {
        climb(spots: 3)
        let y = Double(route.position.y)
        let pressed = route.pressStageLimit()
        XCTAssertEqual(pressed.instruction, .stageLimit)
        XCTAssertEqual(try XCTUnwrap(route.guide.stageLimits.minY), y, accuracy: 1e-9)
        XCTAssertNil(route.guide.stageLimits.maxY)
        // The last stretch is taken as an edge spot, then the column comes back down.
        for _ in 0..<3 where !route.last.stateName.hasSuffix("down") { route.visitTarget() }
        XCTAssertEqual(route.last.stateName, "column 1 down")
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
    }

    func testColumnTwoUpLegStopsAtTheSameLimitWithoutATap() throws {
        climb(spots: 3)
        let top = Double(route.position.y)
        route.pressStageLimit()
        // Down column 1 until its bottom edge, which the helper reaches normally.
        var guardCount = 0
        while route.last.stateName == "column 1 down" || route.last.stateName == "column 1 edge spot"
            || route.last.stateName == "column 1 up", guardCount < 30
        {
            guardCount += 1
            if guardCount > 4 {
                route.feed(move: CGPoint(x: 0, y: 0.1), times: 4)
                route.feed(.edgeAhead, times: 14)
                route.feed(ScriptedRoute.Frame(still: true), times: 14)
            } else {
                route.visitTarget()
            }
        }
        XCTAssertEqual(route.last.stateName, "step right", route.last.stateName)
        // Step right and take column 2 (it starts down, as column 1 ended).
        route.visitTarget()
        XCTAssertEqual(route.guide.placements.last?.column, 2)
        // Straight to its bottom edge, then up: the up leg stops at the limit, no tap.
        route.feed(move: CGPoint(x: 0, y: 0.1), times: 3)
        route.feed(.edgeAhead, times: 14)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        XCTAssertEqual(route.last.stateName, "column 2 up")
        let presses = route.instructions.filter { $0 == .stageLimit }.count
        for _ in 0..<30 where route.last.stateName == "column 2 up" { route.visitTarget() }
        let column2 = route.guide.placements.filter { $0.column == 2 }
        let highest = try XCTUnwrap(column2.map { Double($0.position.y) }.min())
        XCTAssertEqual(highest, top, accuracy: 0.11, "the last spot sits on the limit")
        XCTAssertEqual(
            route.instructions.filter { $0 == .stageLimit }.count, presses, "no second tap")
        XCTAssertNotEqual(route.last.stateName, "column 2 up", "the leg ended there")
    }

    func testALimitOnTheLeftEdgeRunStartsColumnOneThere() throws {
        route.feed(move: ScriptedRoute.left, times: 15)
        XCTAssertEqual(route.last.stateName, "find left edge")
        let x = Double(route.position.x)
        let pressed = route.pressStageLimit()
        XCTAssertEqual(pressed.instruction, .stageLimit)
        XCTAssertEqual(try XCTUnwrap(route.guide.stageLimits.minX), x, accuracy: 1e-9)
        XCTAssertEqual(pressed.stateName, "column 1 up")
        let target = try XCTUnwrap(pressed.target)
        XCTAssertEqual(Double(target.x), x, accuracy: 1e-9, "inset 0, as after an overshoot")
    }

    func testAStepRightPastTheXMaximumFinishesWithStageLimit() throws {
        route.startColumnOne()
        for _ in 0..<2 { route.visitTarget() }
        // Both ends of column 1 are edges.
        route.feed(move: ScriptedRoute.up, times: 3)
        route.feed(.edgeAhead, times: 14)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        route.feed(move: CGPoint(x: 0, y: 0.1), times: 8)
        route.feed(.edgeAhead, times: 14)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        for _ in 0..<4 where route.last.stateName != "step right" { route.visitTarget() }
        XCTAssertEqual(route.last.stateName, "step right")
        let pressed = route.pressStageLimit()
        XCTAssertTrue(pressed.isFinished)
        XCTAssertEqual(route.guide.finishReason, .stageLimit)
        XCTAssertNotNil(route.guide.stageLimits.maxX)
    }

    func testAStageLimitWhereItDoesNotApplyChangesNothing() {
        let before = route.pressStageLimit()
        XCTAssertEqual(before.instruction, .findSample)
        XCTAssertNil(route.guide.stageLimits.minY)
    }

    func testSweepFinishReasonDecodesOldAndNewValues() throws {
        for (raw, expected) in [
            ("sampleFinished", SweepFinishReason.sampleFinished),
            ("endedByHelper", .endedByHelper), ("storageFull", .storageFull),
            ("stageLimit", .stageLimit),
        ] {
            let decoded = try JSONDecoder().decode(SweepFinishReason.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decoded, expected)
            XCTAssertEqual(decoded.rawValue, raw)
        }
        // A manifest keeps no finish reason, so a manifest saved before this value decodes as before.
        XCTAssertEqual(SweepFinishReason(rawValue: "stageLimit"), .stageLimit)
    }
}
