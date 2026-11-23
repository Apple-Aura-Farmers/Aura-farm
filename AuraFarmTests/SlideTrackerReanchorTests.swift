import XCTest

@testable import AuraFarm

/// `SlideTracker.requestReanchor`: the next frame becomes the anchor and the position carries on.
final class SlideTrackerReanchorTests: XCTestCase {
    private let size = 256
    private lazy var texture = SyntheticFrame.smoothNoise(size: size)
    private lazy var frameSize = CGSize(width: size, height: size)
    private lazy var box = EyepieceField.centreSquare(frameSize: frameSize)
    private var seconds = 0.0

    private func frame(shiftedBy dx: Int) -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { [size, texture] x, y in
            UInt8(texture[y * size + min(max(x - dx, 0), size - 1)])
        }
    }

    @discardableResult
    private func track(_ tracker: SlideTracker, _ buffer: CVPixelBuffer) -> SlideTrackerReading {
        seconds += 0.1
        return tracker.track(buffer, box: box, frameSize: frameSize, seconds: seconds)
    }

    func testReanchorKeepsPositionAndZeroesOffset() {
        let tracker = SlideTracker()
        track(tracker, frame(shiftedBy: 0))
        for index in 1...3 { track(tracker, frame(shiftedBy: index * 5)) }
        let jump = track(tracker, frame(shiftedBy: 30))
        tracker.requestReanchor()
        let anchored = track(tracker, frame(shiftedBy: 35))
        XCTAssertEqual(anchored.event, .reanchor)
        XCTAssertEqual(anchored.position.x, 35, accuracy: 3)
        XCTAssertGreaterThan(anchored.position.x, jump.position.x)
        // The next frame is measured against the new anchor: only the 4 px since.
        let next = track(tracker, frame(shiftedBy: 39))
        XCTAssertEqual(next.anchorOffset?.x ?? 99, 4, accuracy: 2)
        XCTAssertEqual(next.position.x, 39, accuracy: 3)
        XCTAssertEqual(next.trackingState, .tracking)
    }

    /// A reading beyond the trust limit (an unreliable match after a big slip at 100x) is never
    /// committed by a requested re-anchor: the position does not jump to it.
    func testReanchorIgnoresUntrustedOffset() {
        let tracker = SlideTracker()
        var wild = false
        tracker.anchorReadingOverride = { _, measured in
            wild ? CGPoint(x: 500, y: 0) : measured
        }
        tracker.frameShiftOverride = { _, measured in wild ? nil : measured }
        track(tracker, frame(shiftedBy: 0))
        for index in 1...3 { track(tracker, frame(shiftedBy: index * 5)) }
        let before = track(tracker, frame(shiftedBy: 15)).position
        wild = true
        tracker.requestReanchor()
        let reading = track(tracker, frame(shiftedBy: 15))
        XCTAssertNotEqual(reading.event, .reanchor)
        XCTAssertEqual(reading.position.x, before.x, accuracy: 3)
    }

    func testReanchorWhileLostRebasesAndTracksAgain() {
        let tracker = SlideTracker()
        var broken = false
        tracker.anchorReadingOverride = { _, measured in
            broken ? nil : measured
        }
        tracker.frameShiftOverride = { _, measured in broken ? nil : measured }
        track(tracker, frame(shiftedBy: 0))
        for index in 1...3 { track(tracker, frame(shiftedBy: index * 5)) }
        broken = true
        var reading = track(tracker, frame(shiftedBy: 20))
        for _ in 0..<4 { reading = track(tracker, frame(shiftedBy: 20)) }
        XCTAssertEqual(reading.trackingState, .lost)
        let known = reading.position
        broken = false
        tracker.requestReanchor()
        let anchored = track(tracker, frame(shiftedBy: 20))
        XCTAssertEqual(anchored.event, .reanchor)
        XCTAssertEqual(anchored.position, known)
        let next = track(tracker, frame(shiftedBy: 24))
        XCTAssertEqual(next.trackingState, .tracking)
        XCTAssertEqual(next.position.x, known.x + 4, accuracy: 3)
    }

    private func flatFrame() -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { _, _ in 90 }
    }

    /// The distance lands on the very next frame, even with no detail (so "End column here" on an
    /// empty patch places the limit after the crossing); tracking starts afresh from the first
    /// frame with detail and carries on from the moved position.
    func testBlindOffsetAddsExactlyAndTracksAgain() {
        let tracker = SlideTracker()
        track(tracker, frame(shiftedBy: 0))
        for index in 1...3 { track(tracker, frame(shiftedBy: index * 5)) }
        var reading = track(tracker, frame(shiftedBy: 15))
        for _ in 0..<6 { reading = track(tracker, flatFrame()) }
        XCTAssertFalse(reading.hasDetail)
        let before = reading.position
        tracker.requestReanchor(addingOffset: CGPoint(x: 40, y: -10))
        let jump = track(tracker, flatFrame())
        XCTAssertEqual(jump.event, .blindReanchor)
        XCTAssertEqual(jump.position.x, before.x + 40, accuracy: 1e-6)
        XCTAssertEqual(jump.position.y, before.y - 10, accuracy: 1e-6)
        var back = jump
        for _ in 0..<10 where back.trackingState != .tracking {
            back = track(tracker, frame(shiftedBy: 15))
        }
        XCTAssertEqual(back.trackingState, .tracking)
        XCTAssertEqual(back.position.x, before.x + 40, accuracy: 1e-6)
        let next = track(tracker, frame(shiftedBy: 19))
        XCTAssertEqual(next.trackingState, .tracking)
        XCTAssertEqual(next.position.x, before.x + 40 + 4, accuracy: 3)
    }
}
