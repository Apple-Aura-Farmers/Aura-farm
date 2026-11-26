import CoreVideo
import XCTest

@testable import AuraFarm

/// Performance step 3, parts B and D and the logging: what each heat mode changes, and that
/// "normal" changes nothing.
final class HeatModeBehaviourTests: XCTestCase {
    private func reason(
        heat: HeatMode, since: Double? = nil, stillSeconds: Double = 0, speed: Double = 0.05,
        view: ViewClass = .sample, tracking: TrackingState = .tracking
    ) -> String? {
        LiveOrganismCounter.skipReason(
            tracking: tracking, isGhostOrSparseSkip: false, monitorPaused: false, viewClass: view,
            speedFraction: speed, stillSeconds: stillSeconds, secondsSinceLastDetection: since,
            heat: heat)
    }

    // MARK: Skip reasons

    func testNormalGivesTheSameReasonsAsBeforeTheHeatMode() {
        // Every row: what the rule gave before heat existed.
        let table: [(since: Double?, still: Double, speed: Double, view: ViewClass, expected: String?)] = [
            (nil, 0, 0.05, .sample, nil), (0.1, 0, 0.05, .sample, nil),
            (0.1, 0, 0.5, .sample, "too_fast"), (0.1, 0, 0.05, .blank, "no_sample"),
            (0.5, 2, 0.05, .sample, "unchanged"), (1.5, 2, 0.05, .sample, nil),
        ]
        for row in table {
            XCTAssertEqual(
                reason(
                    heat: .normal, since: row.since, stillSeconds: row.still, speed: row.speed, view: row.view
                ),
                row.expected)
        }
        XCTAssertEqual(reason(heat: .normal, tracking: .paused), "not_tracking")
    }

    func testCoolDownHoldsTheModelToFourRunsASecond() {
        XCTAssertEqual(reason(heat: .coolDown, since: 0.2), "heat")
        XCTAssertNil(reason(heat: .coolDown, since: 0.34))
        XCTAssertNil(reason(heat: .coolDown, since: nil), "the first run goes")
    }

    func testUnchangedStillWinsOverHeatWhenStill() {
        XCTAssertEqual(reason(heat: .coolDown, since: 0.2, stillSeconds: 2), "unchanged")
        XCTAssertEqual(reason(heat: .tooHot, since: 0.2, stillSeconds: 2), "unchanged")
        XCTAssertEqual(reason(heat: .coolDown, since: 0.2, speed: 0.5), "too_fast")
    }

    func testTooHotSkipsEveryFrame() {
        XCTAssertEqual(reason(heat: .tooHot, since: nil), "heat_critical")
        XCTAssertEqual(reason(heat: .tooHot, since: 5), "heat_critical")
    }

    // MARK: A run through the session

    private func buffer() -> CVPixelBuffer {
        SyntheticFrame.make(width: 64, height: 64) { _, _ in 100 }
    }

    /// Ten seconds at 0.12 s a frame, moving; the heat mode for each frame from `mode`.
    private func run(mode: (Double) -> HeatMode) -> (ran: Int, skips: [String: Int]) {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func hit() {
                lock.lock()
                n += 1
                lock.unlock()
            }
            var value: Int {
                lock.lock()
                defer { lock.unlock() }
                return n
            }
        }
        let runs = Counter()
        let session = LiveCountSession(detect: { _, _ in
            runs.hit()
            return ([], OrganismDetector.Timing())
        })
        session.setCounting(true)
        let frame = buffer()
        var time = 0.0
        while time < 10 - 1e-9 {
            time += 0.12
            let skip = LiveOrganismCounter.skipReason(
                tracking: .tracking, isGhostOrSparseSkip: false, monitorPaused: false,
                viewClass: .sample, speedFraction: 0.05, stillSeconds: 0,
                secondsSinceLastDetection: session.secondsSinceDetection(at: time), heat: mode(time))
            _ = session.process(
                buffer: frame, skipReason: skip, pictureMoved: CGPoint(x: 4, y: 0),
                trackerPosition: .zero, frameSize: CGSize(width: 64, height: 64), fieldCircle: nil,
                seconds: time, column: 1)
            session.drain()
        }
        return (runs.value, session.counter.framesSkippedByReason)
    }

    func testNormalRunsTheModelOnEveryMovingFrame() {
        let result = run { _ in .normal }
        XCTAssertEqual(result.ran, 84)
        XCTAssertTrue(result.skips.isEmpty)
    }

    func testCoolDownRunsTheModelAtMostFourTimesASecond() {
        let result = run { _ in .coolDown }
        XCTAssertLessThanOrEqual(result.ran, 41, "4 a second over 10 s")
        XCTAssertGreaterThan(result.ran, 24)
        XCTAssertEqual(result.skips["heat"], 84 - result.ran, "every other frame is a carried skip")
    }

    func testTooHotRunsNoModelAndLeavingItResumesCounting() {
        let result = run { $0 < 5 ? .tooHot : .normal }
        XCTAssertEqual(result.skips["heat_critical"], 41)
        XCTAssertEqual(result.ran, 84 - 41, "every frame after the heat goes")
    }

    // MARK: The card

    func testTheTooHotCardShowsAtOnceAndGoesWhenTheModeLeaves() {
        var presenter = GuidedScanPresenter()
        func input(_ seconds: Double, hot: Bool, finished: Bool = false) -> GuidedScanInput {
            GuidedScanInput(
                seconds: seconds, instruction: .refocus, arrow: nil, questionID: nil, column: 1,
                lastColumn: false, slipHeightFields: nil, sideInsetFields: nil, captureCount: 0,
                isFinished: finished, isTooHot: hot)
        }
        XCTAssertEqual(presenter.present(input(0, hot: false)).card, .refocus)
        XCTAssertEqual(presenter.present(input(0.1, hot: true)).card, .tooHot, "at once")
        XCTAssertEqual(presenter.present(input(5, hot: true)).card, .tooHot, "held")
        XCTAssertEqual(presenter.present(input(5.1, hot: false)).card, .tooHot, "waits to be steady")
        XCTAssertEqual(presenter.present(input(6, hot: false)).card, .refocus, "then the normal cards")
        XCTAssertEqual(presenter.present(input(7, hot: true, finished: true)).card, .finished)
        XCTAssertEqual(HelperInstruction.tooHot.text, "The phone is too hot. Let it cool for a minute")
    }

    // MARK: The edge probe

    func testTheEdgeProbeRunsOnEveryFourthFrameInCoolDownAndEverySecondAgain() throws {
        let pipeline = SlideMovementPipeline()
        pipeline.requiresReview = true
        let frame = SyntheticFrame.make(width: 1280, height: 720) { x, y in
            hypot(Double(x) - 640, Double(y) - 360) <= 300
                ? UInt8(170 + 60 * sin(Double(x) * 0.5) * sin(Double(y) * 0.5)) : 10
        }
        var seconds = 0.0
        func step() -> SlideMovementStep? {
            seconds += 0.1
            return pipeline.process(frame, seconds: seconds, measureAgreement: false)
        }
        for _ in 0..<31 { _ = step() }
        pipeline.confirmField()
        let probe = EdgeLineProbe()
        func runs(frames: Int) throws -> Int {
            var count = 0
            for _ in 0..<frames {
                let tracked = try XCTUnwrap(step())
                let before = probe.milliseconds
                _ = probe.update(frame, step: tracked, direction: CGPoint(x: 1, y: 0))
                if probe.milliseconds != before { count += 1 }
            }
            return count
        }
        _ = try runs(frames: 2)
        XCTAssertEqual(try runs(frames: 24), 12, "every 2nd frame when normal")
        probe.frameStep = 4
        XCTAssertEqual(try runs(frames: 24), 6, "every 4th frame in cool down")
        probe.frameStep = EdgeLineProbe.everyNthFrame
        XCTAssertEqual(try runs(frames: 24), 12, "every 2nd again")
    }

    // MARK: Logging

    func testTheRunRecordKeepsHeatSecondsAndAnOldRecordStillDecodes() throws {
        var record = GuideRunRecord(
            started: Date(timeIntervalSince1970: 0), ended: Date(timeIntervalSince1970: 60),
            finishReason: .endedByHelper, spotMode: "brief_touch", coverageStep: 1.6, columns: 2,
            spotsTicked: 3, missedSpots: 0, elapsedSeconds: 60, secondsPerSpot: 20, coverageShare: nil,
            countsByLabel: [:], tallyCountsByLabel: [:], totalCount: 0, minimumConfidence: 0.3,
            cropToEyepiece: true, classNames: [], framesCounted: 0, framesSkippedByReason: [:])
        record.heatSeconds = ["normal": 40, "cool_down": 15, "too_hot": 5]
        let data = try GuideRunRecord.encoder().encode(record)
        XCTAssertEqual(try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data), record)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "heatSeconds")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: old).heatSeconds, [:])
    }

    func testTheCSVHasHeatModeAndScreenBrightnessAfterTheKnobWords() {
        // By name, not counted from the end: columns keep being appended after these.
        let knob = MovementLog.header.firstIndex(of: "knob_words")
        XCTAssertEqual(
            Array(MovementLog.header[((knob ?? -1) + 1)...].prefix(2)),
            ["heat_mode", "screen_brightness"])
    }
}
