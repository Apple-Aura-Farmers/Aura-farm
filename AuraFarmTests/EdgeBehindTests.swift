import XCTest

@testable import AuraFarm

/// Phase 2r part B: a line that passes the rule but sits just behind the cross (the helper went
/// past it, 16 Nov 2026 22:56 top edge at offset -0.23 to -0.38) says "come back", not "refocus".
final class EdgeBehindTests: XCTestCase {
    private let left = CGPoint(x: -0.1, y: 0)
    private let right = CGPoint(x: 0.1, y: 0)
    private let up = CGPoint(x: 0, y: -0.1)
    private let down = CGPoint(x: 0, y: 0.1)

    /// The 22:56 line: strength 11, angle -36, little beyond it.
    private func line(_ offset: Double, residual: Double? = nil) -> EdgeLine {
        EdgeLine(
            strength: 11, coverage: 1, longestRun: 8, angleDegrees: -36, offsetFields: offset,
            sign: 1, slideResidualFields: residual, path: [], isCandidate: true,
            beforeEnergy: 10, beyondEnergy: 0.9)
    }

    /// Column 1, helper on the column and past the first spots, heading up.
    private func columnOne() -> ScriptedRoute {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        var offset = 1.0
        while offset >= 0.1 - 1e-9 {
            route.feed(
                ScriptedRoute.Frame(line: LineFor.line(offset)), move: left)
            offset -= 0.1
        }
        route.feed(ScriptedRoute.Frame(still: true, line: LineFor.line(0.1)), times: 24)
        route.answer(.yes)
        route.feed(move: right, times: 6)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        route.feed(move: up, times: 8)
        return route
    }

    private func isBehind(_ instruction: GuideInstruction) -> Bool {
        if case .edgeBehind = instruction { return true }
        return false
    }

    func testTheReplayOfTheOvershotTopEdgeSaysEdgeBehindNotRefocus() {
        let route = columnOne()
        // Still, on clear glass (blurry box), the line 0.23 to 0.36 behind the cross.
        let offsets = [-0.23, -0.30, -0.36, -0.33, -0.28]
        for index in 0..<30 {
            route.feed(
                ScriptedRoute.Frame(
                    viewClass: .blurry, still: true, box: 40,
                    line: line(offsets[index % offsets.count])))
        }
        let tail = route.steps.suffix(30)
        XCTAssertTrue(tail.contains { isBehind($0.instruction) })
        XCTAssertFalse(tail.contains { $0.instruction == .refocus }, "no refocus while the line is seen")
        XCTAssertEqual(route.last.edge.lineState, "behind")
        XCTAssertEqual(route.last.instruction.csvName, "edge_behind")
        if case .edgeBehind(let toward) = route.last.instruction {
            XCTAssertEqual(toward, CGPoint(x: 0, y: 1), "back along the up leg")
        }
    }

    func testComingBackWithMatchingMovementReachesTheConfirmStage() {
        let route = columnOne()
        route.feed(ScriptedRoute.Frame(still: true, line: line(-0.33)), times: 6)
        XCTAssertEqual(route.last.edge.lineState, "behind")
        var offset = -0.33
        while offset < -0.1 + 1e-9 {
            offset += 0.1
            route.feed(ScriptedRoute.Frame(line: line(offset, residual: 0.04)), move: down)
        }
        route.feed(ScriptedRoute.Frame(still: true, line: line(-0.1)), times: 24)
        XCTAssertTrue(route.last.edge.lineAtCross, "state \(route.last.edge.lineState)")
        XCTAssertEqual(route.last.instruction, .edgeDetected)
    }

    func testALineOneFieldBehindIsIgnored() {
        let route = columnOne()
        route.feed(ScriptedRoute.Frame(still: true, line: line(-1.0)), times: 10)
        XCTAssertEqual(route.last.edge.lineState, "none")
        XCTAssertFalse(route.instructions.contains { isBehind($0) })
    }

    func testAKnownEdgeBehindIsIgnored() {
        // An edge confirmed at (0, -2) along the up heading (0, -1); coming back down, the same
        // line is 0.3 behind a helper at y -1.7 (heading (0, 1)): the same edge, not a new one.
        var memory = LineEdgeMemory()
        memory.recordKnown(
            LineEdgeMemory.entry(
                normal: CGPoint(x: 0, y: -1), position: CGPoint(x: 0, y: -2), offsetFields: 0,
                angleDegrees: -36))
        let thresholds = LineEdgeThresholds()
        XCTAssertTrue(
            memory.ignores(
                normal: CGPoint(x: 0, y: 1), position: CGPoint(x: 0, y: -1.7),
                offsetFields: -0.3, angleDegrees: 36, thresholds: thresholds))
        XCTAssertFalse(
            memory.ignores(
                normal: CGPoint(x: 0, y: 1), position: CGPoint(x: 0, y: -0.7),
                offsetFields: -0.3, angleDegrees: 36, thresholds: thresholds), "another line")
    }

    func testTheNewWordsAndTheSnapshotReason() {
        let back = GuideInstruction.edgeBehind(toward: CGPoint(x: 0, y: 1))
        XCTAssertEqual(back.helperText, "Edge just behind you. Come back until it's on the cross")
        XCTAssertTrue(SnapshotTrigger.reasons.contains("edge_behind"))
        var trigger = SnapshotTrigger()
        XCTAssertTrue(
            trigger.update(
                edgeReason: "edge_behind", edgeVerdict: "off", instruction: "edge_behind",
                lineCandidate: nil))
    }
}

/// The 2p line shape for the approach to the left edge.
private enum LineFor {
    static func line(_ offset: Double) -> EdgeLine {
        EdgeLine(
            strength: 30, coverage: 1, longestRun: 8, angleDegrees: 0, offsetFields: offset,
            sign: 1, slideResidualFields: offset > 0.15 ? 0.05 : nil, path: [], isCandidate: true,
            beforeEnergy: nil, beyondEnergy: nil)
    }
}
