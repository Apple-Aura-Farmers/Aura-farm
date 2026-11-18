#if DEBUG
    import CoreGraphics
    import CoreVideo
    import XCTest

    @testable import AuraFarm

    /// Phase 2s-D part A: the model runs on its own queue, so the analysis call never waits for it.
    /// The detector here is a stand-in that sleeps, so timing is under the test's control.
    final class DetectorQueueTests: XCTestCase {
        private let frameSize = CGSize(width: 1280, height: 720)

        /// A tiny buffer whose first byte says which frame it is.
        private func buffer(frame: Int) throws -> CVPixelBuffer {
            var made: CVPixelBuffer?
            CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &made)
            let buffer = try XCTUnwrap(made)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                base.storeBytes(of: UInt8(frame), as: UInt8.self)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return buffer
        }

        private func frameNumber(_ buffer: CVPixelBuffer) -> Int {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            return Int(CVPixelBufferGetBaseAddress(buffer)?.load(as: UInt8.self) ?? 0)
        }

        /// A detector that takes `milliseconds` and finds one Volvox that sits still on the slide:
        /// on screen it is `shiftPerFrame` px further along each frame.
        private func session(milliseconds: Double, shiftPerFrame: Double = 0) -> LiveCountSession {
            LiveCountSession { [self] buffer, _ in
                Thread.sleep(forTimeInterval: milliseconds / 1000)
                let x = 100 + Double(frameNumber(buffer)) * shiftPerFrame
                let box = CGRect(
                    x: x / frameSize.width, y: 0.5, width: 20 / frameSize.width,
                    height: 20 / frameSize.height)
                return (
                    [OrganismDetector.Detection(label: "Volvox", confidence: 0.9, box: box)],
                    OrganismDetector.Timing(
                        preMilliseconds: 1, inferMilliseconds: milliseconds, decodeMilliseconds: 0.5)
                )
            }
        }

        @discardableResult
        private func send(
            _ session: LiveCountSession, frame: Int, moved: CGPoint = .zero
        ) throws -> LiveCountFrameLog {
            session.process(
                buffer: try buffer(frame: frame), skipReason: nil, pictureMoved: moved,
                trackerPosition: .zero, frameSize: frameSize, fieldCircle: nil,
                seconds: Double(frame) * 0.1, column: 1)
        }

        func testASlowDetectorMakesAboutEveryOtherFrameBusyAndTheCallReturnsAtOnce() throws {
            let live = session(milliseconds: 150)
            var busy = 0
            var slowest = 0.0
            for frame in 0..<20 {
                let started = Date()
                let log = try send(live, frame: frame)
                slowest = max(slowest, Date().timeIntervalSince(started))
                if log.skipReason == "busy" { busy += 1 }
                Thread.sleep(forTimeInterval: 0.1)
            }
            live.drain()
            XCTAssertLessThan(slowest, 0.05, "the analysis call never waits for the model")
            XCTAssertTrue((7...13).contains(busy), "\(busy) of 20 frames were busy")
            XCTAssertEqual(live.counter.framesSkippedByReason["busy"], busy)
            XCTAssertEqual(live.counter.framesCounted, 20 - busy)
        }

        func testNoShiftIsLostAcrossBusyFramesSoAStillOrganismIsOneTrack() throws {
            // 30 px a frame on a 20 px box: a lost shift would be a new organism.
            let live = session(milliseconds: 150, shiftPerFrame: 30)
            for frame in 0..<14 {
                try send(live, frame: frame, moved: CGPoint(x: 30, y: 0))
                Thread.sleep(forTimeInterval: 0.1)
            }
            live.drain()
            let counter = live.counter
            XCTAssertGreaterThan(counter.framesSkippedByReason["busy"] ?? 0, 3)
            XCTAssertEqual(counter.tallyTotal, 1, "the same track across the busy frames")
            XCTAssertEqual(counter.helperTotal, 1)
        }

        func testAResetDuringADetectionDropsTheLateResult() throws {
            let live = session(milliseconds: 200)
            try send(live, frame: 1)
            Thread.sleep(forTimeInterval: 0.05)
            live.begin(stamp: "test")
            live.drain()
            XCTAssertEqual(live.counter.framesCounted, 0, "the late result was not counted")
            XCTAssertNil(live.takeCompleted(), "nor logged")
            // The next frame is looked at normally: the flag was freed.
            try send(live, frame: 2)
            live.drain()
            XCTAssertEqual(live.counter.framesCounted, 1)
        }

        func testOnlyOneBufferIsHeldAndEachResultIsHandedOutOnce() throws {
            let live = session(milliseconds: 100)
            var logs: [LiveCountFrameLog] = []
            for frame in 0..<6 {
                try send(live, frame: frame)
                if let done = live.takeCompleted() { logs.append(done) }
                Thread.sleep(forTimeInterval: 0.05)
            }
            live.drain()
            while let done = live.takeCompleted() { logs.append(done) }
            XCTAssertEqual(logs.count, live.counter.framesCounted)
            XCTAssertEqual(Set(logs.compactMap(\.frameSeconds)).count, logs.count, "none twice")
            XCTAssertTrue(logs.allSatisfy { $0.ran && $0.inferMilliseconds == 100 })
        }

        func testCountingStartingIsANoteOnTheQueue() {
            let live = session(milliseconds: 0)
            live.setCounting(true)
            live.drain()
            XCTAssertTrue(live.isCounting)
            live.setCounting(false)
            live.drain()
            XCTAssertFalse(live.isCounting)
        }
    }
#endif
