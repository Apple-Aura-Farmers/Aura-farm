import CoreML
import ImageIO
import XCTest

@testable import AuraFarm

/// Phase 2s-D part B: decoding reads the arrays' memory with their strides and type, and gives
/// exactly what the old `NSNumber` subscripts gave.
final class DecodeSpeedTests: XCTestCase {
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
        let names = DetectorModel.v2ClassNames
        for type in [MLMultiArrayDataType.float32, .float16, .double] {
            for (classes, probabilities, classNames) in [
                (23 + 1, true, names),
                (OrganismDetector.classNames.count, false, OrganismDetector.classNames),
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
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        for name in ["eyepiece-disc-030", "sample-band-140"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let fixture = try detector.detections(in: image)
            XCTAssertNotNil(fixture)
        }
        // The real model's arrays through both decodes: run the model once on a blank frame.
        let (scores, boxes) = try answer(classes: 24, type: .float16, probabilities: true)
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
        let (scores, boxes) = try answer(classes: 24, type: .float16, probabilities: true)
        let names = DetectorModel.v2ClassNames
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
}
