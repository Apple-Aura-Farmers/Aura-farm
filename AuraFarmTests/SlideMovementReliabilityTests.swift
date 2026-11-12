#if DEBUG
    import XCTest

    @testable import AuraFarm

    /// Phase 1f: false jumps, blank glass and the readings around them, through the pipeline.
    final class SlideMovementReliabilityTests: XCTestCase {
        private let width = 1280
        private let height = 720
        private lazy var texture = SyntheticFrame.smoothNoise(size: width)

        /// A static round field of radius 285 about the middle, texture inside it.
        private func ringFrame(shiftedBy dx: Int) -> CVPixelBuffer {
            SyntheticFrame.make(width: width, height: height) { [self] x, y in
                guard hypot(Double(x) - 640, Double(y) - 360) <= 285 else { return 2 }
                return UInt8(70 + texture[y * width + min(max(x - dx, 0), width - 1)] * 0.5)
            }
        }

        /// The same ring with nothing in it: blank glass.
        private func blankFrame() -> CVPixelBuffer {
            SyntheticFrame.make(width: width, height: height) { x, y in
                hypot(Double(x) - 640, Double(y) - 360) <= 285 ? 90 : 2
            }
        }

        private func learned() -> SlideMovementPipeline {
            let pipeline = SlideMovementPipeline()
            for index in 0..<FieldMaskThresholds().framesToLearn {
                _ = pipeline.process(
                    ringFrame(shiftedBy: 0), seconds: Double(index) * 0.1, measureAgreement: false)
            }
            return pipeline
        }

        func testFalseAnchorReadingsArePredictedAndNothingIsLost() throws {
            let pipeline = learned()
            // Every 5th anchor reading is replaced by a fake 250 px one.
            pipeline.anchorReadingOverride = { index, measured in
                index % 5 == 0 ? CGPoint(x: 250, y: 4) : measured
            }
            var seconds = 10.0
            _ = pipeline.process(ringFrame(shiftedBy: 0), seconds: seconds, measureAgreement: false)
            var predicted = 0
            var measuredCount = 0
            var last: SlideMovementStep?
            var lost = 0
            for index in 1...15 {
                seconds += 0.1
                let step = try XCTUnwrap(
                    pipeline.process(
                        ringFrame(shiftedBy: index * 20), seconds: seconds, measureAgreement: false))
                if step.reading == "predicted" { predicted += 1 }
                if step.reading == "measured" { measuredCount += 1 }
                if step.isLost { lost += 1 }
                last = step
            }
            let final = try XCTUnwrap(last)
            print(
                "pipeline false jumps: position \(final.position) hops \(final.hops) predicted \(predicted) measured \(measuredCount) lost \(lost) box \(final.boxSide)"
            )
            XCTAssertEqual(lost, 0)
            XCTAssertEqual(final.gaps, 0)
            XCTAssertEqual(predicted, 3, "readings 5, 10 and 15 were fake")
            XCTAssertEqual(final.position.x, 300, accuracy: 20)
            XCTAssertEqual(final.position.y, 0, accuracy: 10)
        }

        func testABlankStretchIsNoDetailNotLostAndAddsNoDistance() throws {
            let pipeline = learned()
            var seconds = 10.0
            _ = pipeline.process(ringFrame(shiftedBy: 0), seconds: seconds, measureAgreement: false)
            var step: SlideMovementStep?
            for index in 1...5 {
                seconds += 0.1
                step = pipeline.process(
                    ringFrame(shiftedBy: index * 20), seconds: seconds, measureAgreement: false)
            }
            let before = try XCTUnwrap(step)
            XCTAssertTrue(before.hasDetail)
            XCTAssertGreaterThan(before.boxStats.sharpness, DetailThresholds().minBoxSharpness)

            var blind: SlideMovementStep?
            for _ in 0..<10 {
                seconds += 0.1
                blind = pipeline.process(blankFrame(), seconds: seconds, measureAgreement: false)
                XCTAssertFalse(try XCTUnwrap(blind).isLost)
            }
            let inBlank = try XCTUnwrap(blind)
            XCTAssertFalse(inBlank.hasDetail)
            XCTAssertEqual(inBlank.blindStretches, 1)
            XCTAssertNil(inBlank.usedOffset)
            XCTAssertEqual(inBlank.position.x, before.position.x, accuracy: 25)
            XCTAssertEqual(inBlank.gaps, 0)

            // Detail returns: re-anchor on the first good frame, then carry on from there.
            var resumed: SlideMovementStep?
            for index in 0..<8 {
                seconds += 0.1
                resumed = pipeline.process(
                    ringFrame(shiftedBy: 120 + index * 20), seconds: seconds, measureAgreement: false)
            }
            let after = try XCTUnwrap(resumed)
            print(
                "blank stretch: before \(before.position) blank \(inBlank.position) after \(after.position)")
            XCTAssertTrue(after.hasDetail)
            XCTAssertFalse(after.isLost)
            XCTAssertEqual(after.blindStretches, 1)
            XCTAssertGreaterThan(after.position.x, before.position.x + 40, "it follows again")
        }

        /// Prints what one tracked frame costs the old way (region on the newer frame, two
        /// registrations) and the new way (two box registrations plus the box statistics).
        /// A Simulator's CPU, not a phone's: a comparison, not a budget. Nothing is asserted
        /// but that both ran.
        func testPerFrameCostOldAgainstNew() throws {
            let frames = (0..<8).map { ringFrame(shiftedBy: $0 * 20) }
            let size = CGSize(width: width, height: height)
            let box = CGRect(x: 461, y: 181, width: 358, height: 358)
            let clock = ContinuousClock()

            let shake = ShakeEstimator()
            let travel = TravelSinceLastFrame()
            let region = EyepieceField.visionRegion(of: box, frameSize: size)
            shake.regionOfInterest = region
            travel.regionOfInterest = region
            travel.hold(frames[0])
            let old = clock.measure {
                for frame in frames.dropFirst() {
                    _ = shake.update(with: frame)
                    _ = travel.offset(to: frame)
                }
            }

            let registration = BoxRegistration()
            let new = clock.measure {
                for index in 1..<frames.count {
                    _ = registration.offset(from: frames[index - 1], to: frames[index], box: box)
                    _ = registration.offset(from: frames[0], to: frames[index], box: box)
                    _ = FrameAnalyzer.stats(of: frames[index], in: box, step: 4)
                }
            }
            let count = Double(frames.count - 1)
            func ms(_ duration: Duration) -> Double {
                (Double(duration.components.seconds) * 1000
                    + Double(duration.components.attoseconds) / 1e15) / count
            }
            print(String(format: "per tracked frame: old %.1f ms, new %.1f ms", ms(old), ms(new)))
        }
    }
#endif
