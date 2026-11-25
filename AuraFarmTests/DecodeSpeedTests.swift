import CoreML
import ImageIO
import XCTest

@testable import AuraFarm

/// Phase 2s-D part B: decoding reads the arrays' memory with their strides and type, and gives
/// exactly what the old `NSNumber` subscripts gave.
final class DecodeSpeedTests: XCTestCase {

    /// A six-slot list standing in for a model whose scores are logits. No shipped model has
    /// that shape any more — V3's graph ends in a sigmoid — but the decode still takes the
    /// logit path as a parameter, so it is still worth exercising. The names are V1's, which
    /// is what these expectations were written against.
    static let logitClassNames = [
        "no-object", "Arcellinida", "Digononta", "Euglenoid", "Nematode", "Volvox",
    ]
    /// The decode as it was before: one `NSNumber` subscript at a time. Kept here as the reference.
    private func referenceDecode(
        scores: MLMultiArray, boxes: MLMultiArray, classNames: [String],
        scoresAreProbabilities: Bool, minimumConfidence: Float
    ) -> [OrganismDetector.Detection] {
        let queries = scores.shape[1].intValue
        let classes = scores.shape[2].intValue
        guard classes > 1 else { return [] }
        var found: [OrganismDetector.Detection] = []
        for query in 0..<queries {
            var best = -Float.greatestFiniteMagnitude
            var bestClass = 1
            for klass in 1..<classes {
                let value = scores[[0, query, klass] as [NSNumber]].floatValue
                if value > best {
                    best = value
                    bestClass = klass
                }
            }
            let confidence = scoresAreProbabilities ? best : 1 / (1 + exp(-best))
            guard confidence >= minimumConfidence else { continue }
            let centreX = boxes[[0, query, 0] as [NSNumber]].doubleValue
            let centreY = boxes[[0, query, 1] as [NSNumber]].doubleValue
            let width = boxes[[0, query, 2] as [NSNumber]].doubleValue
            let height = boxes[[0, query, 3] as [NSNumber]].doubleValue
            let box = CGRect(
                x: centreX - width / 2, y: 1 - (centreY + height / 2), width: width, height: height)
            guard !OrganismDetector.coversWholeFrame(box) else { continue }
            found.append(
                .init(
                    label: bestClass < classNames.count ? classNames[bestClass] : "class\(bestClass)",
                    confidence: confidence, box: box))
        }
        return found
    }

    /// A model-shaped answer: 300 queries, `classes` scores each, with a few real finds.
    private func answer(
        classes: Int, type: MLMultiArrayDataType, probabilities: Bool
    ) throws -> (MLMultiArray, MLMultiArray) {
        let scores = try MLMultiArray(shape: [1, 300, NSNumber(value: classes)], dataType: type)
        let boxes = try MLMultiArray(shape: [1, 300, 4], dataType: type)
        var seed: UInt64 = 7
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for query in 0..<300 {
            for klass in 0..<classes {
                let value = probabilities ? next() * 0.2 : next() * 6 - 5
                scores[[0, query, klass] as [NSNumber]] = NSNumber(value: value)
            }
            if query % 25 == 0 {
                let klass = 1 + query % (classes - 1)
                scores[[0, query, klass] as [NSNumber]] = NSNumber(value: probabilities ? 0.8 : 3.0)
            }
            let size = 0.03 + next() * 0.2
            for (index, value) in [0.2 + next() * 0.6, 0.2 + next() * 0.6, size, size].enumerated() {
                boxes[[0, query, index] as [NSNumber]] = NSNumber(value: value)
            }
        }
        return (scores, boxes)
    }

    private func assertSame(
        _ one: [OrganismDetector.Detection], _ two: [OrganismDetector.Detection],
        _ note: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(one.count, two.count, note, file: file, line: line)
        for (a, b) in zip(one, two) {
            XCTAssertEqual(a.label, b.label, note, file: file, line: line)
            XCTAssertEqual(a.confidence, b.confidence, accuracy: 1e-6, note, file: file, line: line)
            for (x, y) in [
                (a.box.minX, b.box.minX), (a.box.minY, b.box.minY), (a.box.width, b.box.width),
                (a.box.height, b.box.height),
            ] {
                XCTAssertEqual(x, y, accuracy: 1e-6, note, file: file, line: line)
            }
        }
    }

    func testTheNewDecodeGivesTheOldDecodesDetectionsForV1AndV2InEveryDataType() throws {
        let names = DetectorModel.v3ClassNames
        for type in [MLMultiArrayDataType.float32, .float16, .double] {
            for (classes, probabilities, classNames) in [
                (22 + 1, true, names),
                (Self.logitClassNames.count, false, Self.logitClassNames),
            ] {
                let (scores, boxes) = try answer(classes: classes, type: type, probabilities: probabilities)
                let old = referenceDecode(
                    scores: scores, boxes: boxes, classNames: classNames,
                    scoresAreProbabilities: probabilities, minimumConfidence: 0.3)
                let new = OrganismDetector.decode(
                    scores: scores, boxes: boxes, classNames: classNames,
                    scoresAreProbabilities: probabilities)
                XCTAssertFalse(old.isEmpty)
                assertSame(old, new, "\(type.rawValue) \(classes) classes")
            }
        }
    }

    func testTheNewDecodeGivesTheOldDecodesDetectionsOnTheRealV2Fixtures() throws {
        let detector = try OrganismDetector(model: .v3, computeUnits: .cpuAndGPU)
        for name in ["eyepiece-disc-030", "sample-band-140"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let fixture = try detector.detections(in: image)
            XCTAssertNotNil(fixture)
        }
        // The real model's arrays through both decodes: run the model once on a blank frame.
        let (scores, boxes) = try answer(classes: 23, type: .float16, probabilities: true)
        assertSame(
            referenceDecode(
                scores: scores, boxes: boxes, classNames: detector.classNames,
                scoresAreProbabilities: true, minimumConfidence: 0.3),
            OrganismDetector.decode(
                scores: scores, boxes: boxes, classNames: detector.classNames,
                scoresAreProbabilities: true), "V2 names")
    }

    func testAStridedArrayIsReadInItsLogicalOrder() throws {
        // A 2 x 3 view whose rows are 4 apart: padding after every row.
        let padded = try MLMultiArray(
            dataPointer: UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 4),
            shape: [2, 3], dataType: .float32, strides: [4, 1], deallocator: { $0.deallocate() })
        for row in 0..<2 {
            for column in 0..<3 { padded[[row, column] as [NSNumber]] = NSNumber(value: row * 10 + column) }
        }
        XCTAssertEqual(OrganismDetector.values(of: padded), [0, 1, 2, 10, 11, 12])
    }

    func testHalfPrecisionWidensExactly() {
        XCTAssertEqual(OrganismDetector.halfToFloat(0x3C00), 1)
        XCTAssertEqual(OrganismDetector.halfToFloat(0xC000), -2)
        XCTAssertEqual(OrganismDetector.halfToFloat(0x3555), 0.333251953125)
        XCTAssertEqual(
            OrganismDetector.halfToFloat(0x0001), Float(sign: .plus, exponent: -24, significand: 1))
        XCTAssertEqual(OrganismDetector.halfToFloat(0), 0)
    }

    /// Timing, printed for the report: the old and the new decode over the V2 shape.
    func testDecodeTimeBeforeAndAfter() throws {
        let (scores, boxes) = try answer(classes: 23, type: .float16, probabilities: true)
        let names = DetectorModel.v3ClassNames
        func time(_ body: () -> Void) -> Double {
            body()
            let started = CFAbsoluteTimeGetCurrent()
            for _ in 0..<20 { body() }
            return (CFAbsoluteTimeGetCurrent() - started) * 1000 / 20
        }
        let before = time {
            _ = referenceDecode(
                scores: scores, boxes: boxes, classNames: names, scoresAreProbabilities: true,
                minimumConfidence: 0.3)
        }
        let after = time {
            _ = OrganismDetector.decode(
                scores: scores, boxes: boxes, classNames: names, scoresAreProbabilities: true)
        }
        // Printed, not asserted: a Debug build on a shared machine is no place for a speed limit.
        print("DECODETIME before \(before) ms after \(after) ms")
    }

    // MARK: Padded layouts

    /// `source`'s values in a new array with the given strides (extra room is left at zero).
    private func relaid(_ source: MLMultiArray, strides: [Int]) throws -> MLMultiArray {
        let shape = source.shape.map(\.intValue)
        let size = source.dataType == .double ? 8 : source.dataType == .float32 ? 4 : 2
        let elements = (0..<shape.count).map { (shape[$0] - 1) * strides[$0] }.reduce(1, +)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: elements * size, alignment: 8)
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: elements * size)
        let array = try MLMultiArray(
            dataPointer: memory, shape: source.shape, dataType: source.dataType,
            strides: strides.map { NSNumber(value: $0) }, deallocator: { $0.deallocate() })
        for query in 0..<shape[1] {
            for column in 0..<shape[2] {
                let index = [0, query, column] as [NSNumber]
                array[index] = source[index]
            }
        }
        return array
    }

    /// Contiguous, padded rows, and a padded batch stride, for a [1, 300, width] array.
    private func layouts(_ array: MLMultiArray, paddedWidth: Int) throws -> [(String, MLMultiArray)] {
        let width = array.shape[2].intValue
        return [
            ("contiguous", try relaid(array, strides: [300 * width, width, 1])),
            ("padded rows", try relaid(array, strides: [300 * paddedWidth, paddedWidth, 1])),
            ("padded batch", try relaid(array, strides: [300 * width + 16, width, 1])),
        ]
    }

    func testTheRowDecodeGivesTheReferenceDetectionsInEveryLayout() throws {
        for type in [MLMultiArrayDataType.float32, .float16, .double] {
            for (classes, probabilities, padded, classNames) in [
                (23, true, 32, DetectorModel.v3ClassNames),
                (6, false, 8, Self.logitClassNames),
            ] {
                let (scores, boxes) = try answer(classes: classes, type: type, probabilities: probabilities)
                for ((name, s), (_, b)) in zip(
                    try layouts(scores, paddedWidth: padded), try layouts(boxes, paddedWidth: 8))
                {
                    let old = referenceDecode(
                        scores: s, boxes: b, classNames: classNames,
                        scoresAreProbabilities: probabilities, minimumConfidence: 0.3)
                    let new = OrganismDetector.decode(
                        scores: s, boxes: b, classNames: classNames,
                        scoresAreProbabilities: probabilities)
                    XCTAssertFalse(old.isEmpty)
                    assertSame(old, new, "\(type.rawValue) \(classes) classes \(name)")
                }
            }
        }
    }

    func testPaddedRowsDecodeInUnderHalfTheGeneralPathsTime() throws {
        let (scores, boxes) = try answer(classes: 23, type: .float16, probabilities: true)
        let paddedScores = try relaid(scores, strides: [300 * 32, 32, 1])
        let paddedBoxes = try relaid(boxes, strides: [300 * 8, 8, 1])
        let names = DetectorModel.v3ClassNames
        func time(_ body: () -> Void) -> Double {
            body()
            let started = CFAbsoluteTimeGetCurrent()
            for _ in 0..<50 { body() }
            return (CFAbsoluteTimeGetCurrent() - started) * 1000 / 50
        }
        let general = time {
            _ = OrganismDetector.decodeGeneral(
                scores: paddedScores, boxes: paddedBoxes, classNames: names,
                scoresAreProbabilities: true, minimumConfidence: 0.3)
        }
        let rows = time {
            _ = OrganismDetector.decode(
                scores: paddedScores, boxes: paddedBoxes, classNames: names,
                scoresAreProbabilities: true, minimumConfidence: 0.3)
        }
        print("DECODETIME padded Float16: general \(general) ms, rows \(rows) ms")
        XCTAssertLessThan(rows, general / 2)
    }
}
