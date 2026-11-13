#if DEBUG
    import XCTest

    @testable import AuraFarm

    /// Pins what `SlideMovementPipeline` reports, frame by frame, on deterministic synthetic
    /// runs, so moving the tracking chain into Core cannot change it. The expected rows are
    /// literal, recorded from the code before the move.
    final class SlideMovementCharacterizationTests: XCTestCase {
        private let width = 1280
        private let height = 720
        private lazy var texture = SyntheticFrame.smoothNoise(size: width)
        private var cache: [Int: CVPixelBuffer] = [:]
        private var seconds = 10.0

        /// A static round field with texture that moves inside it.
        private func ringFrame(shiftedBy dx: Int) -> CVPixelBuffer {
            if let cached = cache[dx] { return cached }
            let frame = SyntheticFrame.make(width: width, height: height) { [self] x, y in
                guard hypot(Double(x) - 640, Double(y) - 360) <= 285 else { return 2 }
                return UInt8(70 + texture[y * width + min(max(x - dx, 0), width - 1)] * 0.5)
            }
            cache[dx] = frame
            return frame
        }

        private func blankFrame() -> CVPixelBuffer {
            SyntheticFrame.make(width: width, height: height) { x, y in
                hypot(Double(x) - 640, Double(y) - 360) <= 285 ? 90 : 2
            }
        }

        /// 256 px textured frames for the centre square scenarios.
        private func squareFrame(shiftedBy dx: Int) -> CVPixelBuffer {
            let texture = SyntheticFrame.smoothNoise(size: 256)
            return SyntheticFrame.make(width: 256, height: 256) { x, y in
                UInt8(texture[y * 256 + min(max(x - dx, 0), 255)])
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

        private func f(_ value: Double) -> String { String(format: "%.1f", value) }
        private func pt(_ p: CGPoint?) -> String {
            p.map { "(\(f(Double($0.x))),\(f(Double($0.y))))" } ?? "-"
        }

        /// Every field the tracking reports, as one line.
        private func row(_ s: SlideMovementStep) -> String {
            let rect = s.registrationRect.map {
                "(\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height)))"
            }
            let kind: String
            switch s.fieldState {
            case .learning: kind = "learning"
            case .ready: kind = "ready"
            case .untrusted: kind = "untrusted"
            case nil: kind = "-"
            }
            return "p=\(pt(s.position)) pf=\(pt(s.positionFields)) h=\(s.hops) g=\(s.gaps) "
                + "lost=\(s.isLost) ev=\(s.eventName) r=\(s.reading) st=\(s.predictedStreak) "
                + "d=\(s.hasDetail) bl=\(s.blindStretches) m=\(s.blankReturnsMatched) "
                + "u=\(s.blankReturnsUnmatched) be=\(s.blankReturnEvent) pc=\(s.pictureCheck) "
                + "sm=\(pt(s.startMatch)) rr=\(rect ?? "-") fs=\(kind) "
                + "bs=(\(f(s.boxStats.brightness)),\(f(s.boxStats.sharpness)),\(f(s.boxStats.contrast)))"
        }

        private func feed(_ pipeline: SlideMovementPipeline, _ frame: CVPixelBuffer) throws -> String {
            seconds += 0.1
            return row(
                try XCTUnwrap(pipeline.process(frame, seconds: seconds, measureAgreement: false)))
        }

        private func check(_ name: String, _ rows: [String], _ expected: [String]) {
            if expected.isEmpty { print("RECORD \(name)\n" + rows.joined(separator: "\n")) }
            XCTAssertEqual(rows, expected, name)
        }

        private func squarePipeline() -> SlideMovementPipeline {
            let pipeline = SlideMovementPipeline()
            pipeline.fieldMode = .centreSquare
            return pipeline
        }

        func testA_centreSquareSteadyMoveMakesHops() throws {
            let pipeline = squarePipeline()
            var rows: [String] = []
            for index in 0..<12 { rows.append(try feed(pipeline, squareFrame(shiftedBy: index * 15))) }
            check("a", rows, Expected.a)
        }

        func testB_oneFalseJumpIsPredicted() throws {
            let pipeline = squarePipeline()
            pipeline.anchorReadingOverride = { index, measured in
                index == 3 ? CGPoint(x: 90, y: 0) : measured
            }
            var rows: [String] = []
            for index in 0..<8 { rows.append(try feed(pipeline, squareFrame(shiftedBy: index * 6))) }
            check("b", rows, Expected.b)
        }

        func testC_blankThenMatchedReturn() throws {
            let pipeline = learned()
            var rows: [String] = []
            for _ in 0..<4 { rows.append(try feed(pipeline, ringFrame(shiftedBy: 0))) }
            for _ in 0..<6 { rows.append(try feed(pipeline, blankFrame())) }
            for _ in 0..<8 { rows.append(try feed(pipeline, ringFrame(shiftedBy: 60))) }
            check("c", rows, Expected.c)
        }

        func testD_blankThenUnmatchedReturn() throws {
            let pipeline = learned()
            var rows: [String] = []
            for _ in 0..<4 { rows.append(try feed(pipeline, ringFrame(shiftedBy: 0))) }
            for _ in 0..<6 { rows.append(try feed(pipeline, blankFrame())) }
            for _ in 0..<14 { rows.append(try feed(pipeline, ringFrame(shiftedBy: 200))) }
            check("d", rows, Expected.d)
        }

        func testE_startPictureConfirms() throws {
            let pipeline = learned()
            var rows = [try feed(pipeline, ringFrame(shiftedBy: 0))]
            pipeline.setStartPicture()
            for _ in 0..<2 { rows.append(try feed(pipeline, ringFrame(shiftedBy: 0))) }
            for index in 1...5 { rows.append(try feed(pipeline, ringFrame(shiftedBy: index * 15))) }
            for index in stride(from: 4, through: 0, by: -1) {
                rows.append(try feed(pipeline, ringFrame(shiftedBy: index * 15)))
            }
            for _ in 0..<4 { rows.append(try feed(pipeline, ringFrame(shiftedBy: 0))) }
            check("e", rows, Expected.e)
        }

        func testF_autoLearnsThenTracks() throws {
            let pipeline = SlideMovementPipeline()
            var rows: [String] = []
            for index in 0..<(FieldMaskThresholds().framesToLearn + 10) {
                rows.append(try feed(pipeline, ringFrame(shiftedBy: index * 15)))
            }
            check("f", rows, Expected.f)
        }
    }
#endif
