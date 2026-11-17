import CoreGraphics
import CoreML
import ImageIO
import XCTest

@testable import AuraFarm

/// SoilDetector V2 (the Float16 export) from the app bundle, on the user's own microscope frames.
final class V2DetectorTests: XCTestCase {
    private func frame(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "png"), "missing \(name)")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testV2OpensAndNamesItsTwentyThreeClassesInOrder() throws {
        let started = CFAbsoluteTimeGetCurrent()
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        print("V2TEST open", (CFAbsoluteTimeGetCurrent() - started) * 1000, "ms")
        XCTAssertEqual(detector.kind, .v2)
        XCTAssertEqual(detector.modelName, "SoilDetectorV2")
        XCTAssertEqual(detector.classNames.count, 24, "background and 23 classes")
        XCTAssertEqual(detector.classNames.first, "background")
        XCTAssertEqual(detector.classNames[6], "Didinium_Phacus_Collodictyon")
        XCTAssertEqual(detector.classNames, DetectorModel.v2ClassNames, "metadata matches the built-in list")
        XCTAssertEqual(OrganismDetector.modelName, "SoilDetector", "V1's name is unchanged")
    }

    func testV2RunsOnAFrameAndGivesProbabilities() throws {
        var detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        detector.minimumConfidence = 0.05
        let found = try detector.detections(in: try frame("eyepiece-disc-030"))
        print("V2TEST whole frame", found.map { "\($0.label) \($0.confidence) \($0.box)" })
        XCTAssertTrue(found.allSatisfy { $0.confidence >= 0.05 && $0.confidence <= 1 })
    }
}
