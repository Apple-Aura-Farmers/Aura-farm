import XCTest

@testable import AuraFarm

/// A view that has not moved is not sent to the detector again, except once a second.
final class UnchangedSkipTests: XCTestCase {
    private let size = CGSize(width: 640, height: 480)

    private func found(x: Double) -> OrganismDetector.Detection {
        OrganismDetector.Detection(
            label: "Volvox", confidence: 0.9,
            box: CGRect(x: (x - 20) / 640, y: 1 - 260 / 480, width: 40 / 640, height: 40 / 480))
    }

    /// Mirrors the lab's loop: ask `skipReason`, run the detector on the frames it lets through.
    private struct Loop {
        var counter = LiveOrganismCounter()
        var lastRun: Double?
        var runs = 0
        var reasons: [String?] = []

        mutating func frame(
            at seconds: Double, stillSeconds: Double, detections: [OrganismDetector.Detection]
        ) {
            let reason = LiveOrganismCounter.skipReason(
                tracking: .tracking, isGhostOrSparseSkip: false, monitorPaused: false,
                viewClass: .sample, speedFraction: 0.01, stillSeconds: stillSeconds,
                secondsSinceLastDetection: lastRun.map { seconds - $0 })
            reasons.append(reason)
            if let reason {
                counter.skip(pictureMoved: .zero, reason: reason)
            } else {
                runs += 1
                lastRun = seconds
                counter.update(
                    detections: detections, pictureMoved: .zero, trackerPosition: .zero,
                    frameSize: CGSize(width: 640, height: 480), fieldCircle: nil, seconds: seconds,
                    column: 1)
            }
        }
    }

    func testStandingStillFor2Point5SecondsRunsTheDetectorAtMostThreeTimes() {
        var loop = Loop()
        for index in 1...25 {
            let seconds = Double(index) * 0.1
            // Already still when the window opens, as at an edge hold.
            loop.frame(at: seconds, stillSeconds: 1 + seconds, detections: [])
        }
        XCTAssertLessThanOrEqual(loop.runs, 3, "ran \(loop.runs) times")
        XCTAssertEqual(loop.counter.framesSkippedByReason["unchanged"], 25 - loop.runs)
    }

    func testMovingSteadilyNeverSkipsAsUnchanged() {
        var loop = Loop()
        for index in 1...50 {
            // Never still for 0.3 s: the stillness resets every few readings.
            loop.frame(at: Double(index) * 0.1, stillSeconds: 0.1 * Double(index % 3), detections: [])
        }
        XCTAssertEqual(loop.runs, 50)
        XCTAssertFalse(loop.reasons.contains("unchanged"))
    }

    func testAnOrganismThatAppearsWhileStillIsFoundWithinASecondAndCountedOnItsSecondSighting() {
        var loop = Loop()
        for index in 1...30 {
            let seconds = Double(index) * 0.1
            // It swims in at 1.05 s and stays put on the slide.
            let present = seconds >= 1.05
            loop.frame(at: seconds, stillSeconds: 1 + seconds, detections: present ? [found(x: 300)] : [])
        }
        // First sighting at the next refresh (1.1 s), within a second of appearing; the second
        // one a second later (2.1 s) counts it.
        XCTAssertEqual(loop.counter.helperTotal, 1)
        XCTAssertEqual(loop.counter.tallyTotal, 1)
    }

    func testTheReasonComesAfterTheExistingOnes() {
        let thresholds = LiveCountThresholds()
        XCTAssertEqual(thresholds.stillSecondsBeforeSkip, 0.3)
        XCTAssertEqual(thresholds.refreshSeconds, 1.0)
        let reason = LiveOrganismCounter.skipReason(
            tracking: .tracking, isGhostOrSparseSkip: false, monitorPaused: false, viewClass: .sample,
            speedFraction: 0.5, stillSeconds: 5, secondsSinceLastDetection: 0.2)
        XCTAssertEqual(reason, "too_fast", "an earlier reason wins")
        XCTAssertNil(
            LiveOrganismCounter.skipReason(
                tracking: .tracking, isGhostOrSparseSkip: false, monitorPaused: false,
                viewClass: .sample, speedFraction: 0.01, stillSeconds: 5,
                secondsSinceLastDetection: nil), "never run yet: it goes")
    }
}
