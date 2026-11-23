import CoreVideo
import XCTest

@testable import AuraFarm

/// Performance step 4: the model runs at most 5 times a second (4 in cool-down).
final class ModelRateCapTests: XCTestCase {
    private func reason(
        since: Double?, cap: Double? = 5, heat: HeatMode = .normal, stillSeconds: Double = 0,
        speed: Double = 0.05, tracking: TrackingState = .tracking
    ) -> String? {
        LiveOrganismCounter.skipReason(
            tracking: tracking, isGhostOrSparseSkip: false, monitorPaused: false,
            viewClass: .sample, speedFraction: speed, stillSeconds: stillSeconds,
            secondsSinceLastDetection: since, maxModelRunsPerSecond: cap, heat: heat)
    }

    // MARK: Reasons

    func testWithinTwoTenthsOfARunIsRateAndAfterThatTheFrameGoes() {
        XCTAssertEqual(reason(since: 0.12), "rate")
        XCTAssertEqual(reason(since: 0.19), "rate")
        XCTAssertNil(reason(since: 0.2))
        XCTAssertNil(reason(since: nil), "the first run goes")
    }

    func testCoolDownSharesTheRangeRateUnderTwoTenthsAndHeatUpToAQuarter() {
        XCTAssertEqual(reason(since: 0.1, heat: .coolDown), "rate")
        XCTAssertEqual(reason(since: 0.2, heat: .coolDown), "heat")
        XCTAssertEqual(reason(since: 0.24, heat: .coolDown), "heat")
        XCTAssertNil(reason(since: 0.25, heat: .coolDown))
        XCTAssertEqual(reason(since: 0.24, cap: nil, heat: .coolDown), "heat", "the toggle off: heat alone")
        XCTAssertNil(reason(since: 0.12, cap: nil), "the toggle off, normal: nothing")
    }

    func testTooHotIsHeatCriticalOnEveryFrameAlsoWithinTwoTenthsOfARun() {
        XCTAssertEqual(reason(since: 0.1, heat: .tooHot), "heat_critical")
        XCTAssertEqual(reason(since: 5, heat: .tooHot), "heat_critical")
        XCTAssertEqual(reason(since: nil, heat: .tooHot), "heat_critical")
    }

    func testUnchangedStillWinsAndTheOtherReasonsAreUnchanged() {
        for heat in HeatMode.allCases {
            XCTAssertEqual(reason(since: 0.1, heat: heat, stillSeconds: 2), "unchanged")
        }
        XCTAssertEqual(reason(since: 0.1, speed: 0.5), "too_fast")
        XCTAssertEqual(reason(since: 0.1, tracking: .paused), "not_tracking")
    }

    func testTheCoolDownCapIsFourAndTheNormalCapIsFive() {
        XCTAssertEqual(HeatThresholds().coolDownModelMaxPerSecond, 4)
        XCTAssertEqual(LiveCountThresholds().maxModelRunsPerSecond, 5)
    }

    // MARK: A moving run

    /// Mirrors the engine's loop: ask `skipReason`, run the detector on the frames it lets through,
    /// and hand every frame's picture movement to the counter, run or skip.
    private struct Loop {
        var counter = LiveOrganismCounter()
        var cap: Double?
        var heat = HeatMode.normal
        var lastRun: Double?
        var runs = 0
        var framesShift = 0.0
        var counterShift = 0.0

        mutating func frame(
            at seconds: Double, shift: Double, detections: [OrganismDetector.Detection]
        ) {
            framesShift += shift
            counterShift += shift
            let moved = CGPoint(x: shift, y: 0)
            let reason = LiveOrganismCounter.skipReason(
                tracking: .tracking, isGhostOrSparseSkip: false, monitorPaused: false,
                viewClass: .sample, speedFraction: 0.05, stillSeconds: 0,
                secondsSinceLastDetection: lastRun.map { seconds - $0 }, maxModelRunsPerSecond: cap,
                heat: heat)
            if let reason {
                counter.skip(pictureMoved: moved, reason: reason)
            } else {
                runs += 1
                lastRun = seconds
                counter.update(
                    detections: detections, pictureMoved: moved, trackerPosition: .zero,
                    frameSize: CGSize(width: 640, height: 480), fieldCircle: nil, seconds: seconds,
                    column: 1)
            }
        }
    }

    private func tenSeconds(_ loop: inout Loop) {
        for index in 1...84 { loop.frame(at: Double(index) * 0.12, shift: 3, detections: []) }
    }

    func testWithTheCapOnAtMostFiveRunsASecondAboutEverySecondFrame() {
        var loop = Loop(cap: 5)
        tenSeconds(&loop)
        XCTAssertLessThanOrEqual(loop.runs, 50, "5 a second over 10 s")
        XCTAssertEqual(loop.runs, 42, "every 2nd frame at 0.12 s")
        XCTAssertEqual(loop.counter.framesSkippedByReason["rate"], 84 - loop.runs)
    }

    func testWithTheCapOffEveryEligibleFrameRuns() {
        var loop = Loop(cap: nil)
        tenSeconds(&loop)
        XCTAssertEqual(loop.runs, 84)
        XCTAssertNil(loop.counter.framesSkippedByReason["rate"])
    }

    func testCoolDownRunsAtMostFourTimesASecond() {
        var loop = Loop(cap: 5, heat: .coolDown)
        tenSeconds(&loop)
        XCTAssertLessThanOrEqual(loop.runs, 40, "4 a second over 10 s")
        XCTAssertEqual(loop.runs, 28, "every 3rd frame at 0.12 s")
        // Each run is followed by a frame 0.12 s on ("rate") and one 0.24 s on ("heat").
        XCTAssertEqual(loop.counter.framesSkippedByReason["rate"], loop.runs)
        XCTAssertEqual(loop.counter.framesSkippedByReason["heat"], loop.runs)
    }

    func testTheShiftsTheCounterReceivesAddUpToEveryFramesShift() {
        var loop = Loop(cap: 5)
        tenSeconds(&loop)
        XCTAssertEqual(loop.counterShift, loop.framesShift, accuracy: 1e-9)
        XCTAssertEqual(loop.framesShift, 84 * 3)
    }

    func testAnOrganismSeenWhileMovingIsStillCountedOnceWithTheCapOn() {
        // It stays put on the slide while the picture moves 25 px a frame: two frames apart it is
        // 50 px along, further than its own 40 px box, so only the carried shift lines it up.
        for cap in [5.0, nil] as [Double?] {
            var loop = Loop(cap: cap)
            for index in 1...20 {
                let x = 20.0 + 25.0 * Double(index)
                let detection = OrganismDetector.Detection(
                    label: "Volvox", confidence: 0.9,
                    box: CGRect(x: (x - 20) / 640, y: 1 - 260 / 480, width: 40 / 640, height: 40 / 480))
                loop.frame(at: Double(index) * 0.12, shift: 25, detections: [detection])
            }
            XCTAssertEqual(loop.counter.tallyTotal, 1, "cap \(String(describing: cap))")
            XCTAssertEqual(loop.counter.helperTotal, 1, "cap \(String(describing: cap))")
            if cap != nil { XCTAssertLessThan(loop.runs, 20) }
        }
    }

    func testARateSkipThroughTheSessionIsACarriedSkip() {
        let session = LiveCountSession(detect: { _, _ in ([], OrganismDetector.Timing()) })
        session.setCounting(true)
        let frame = SyntheticFrame.make(width: 64, height: 64) { _, _ in 100 }
        let log = session.process(
            buffer: frame, skipReason: "rate", pictureMoved: CGPoint(x: 4, y: 0),
            trackerPosition: .zero, frameSize: CGSize(width: 64, height: 64), fieldCircle: nil,
            seconds: 1, column: 1)
        session.drain()
        XCTAssertEqual(log.skipReason, "rate")
        XCTAssertEqual(session.counter.framesSkippedByReason["rate"], 1)
    }

    // MARK: The run record

    func testTheRunRecordKeepsTheCapAndAnOldRecordDecodes() throws {
        var record = GuideRunRecord(
            started: Date(timeIntervalSince1970: 0), ended: Date(timeIntervalSince1970: 60),
            finishReason: .endedByHelper, spotMode: "brief_touch", coverageStep: 1.6, columns: 2,
            spotsTicked: 3, missedSpots: 0, elapsedSeconds: 60, secondsPerSpot: 20, coverageShare: nil,
            countsByLabel: [:], tallyCountsByLabel: [:], totalCount: 0, minimumConfidence: 0.3,
            cropToEyepiece: true, classNames: [], framesCounted: 0, framesSkippedByReason: [:])
        record.modelRateCap = 5
        let data = try GuideRunRecord.encoder().encode(record)
        let back = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data)
        XCTAssertEqual(back.modelRateCap, 5)
        XCTAssertEqual(back, record)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "modelRateCap")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: old).modelRateCap)
    }
}
