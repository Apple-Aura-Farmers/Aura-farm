import CoreGraphics
import CoreImage
import CoreML
import ImageIO
import XCTest

@testable import AuraFarm

/// SoilDetector V2 (the Float16 export) from the app bundle, on the user's own 1280 x 720
/// microscope frames: `eyepiece-disc-030` (cover-slip edge, no organism; V2 calls the whole disc
/// Volvox) and `sample-band-140` (the thick sample band at the edge; V2 gives a 0.73 x 0.91 box
/// at about 0.82 with a crop).
final class V2DetectorTests: XCTestCase {
    private let frameSize = CGSize(width: 1280, height: 720)
    /// The eyepiece circle measured on the fixtures: the field detection learns over many
    /// frames and these are single frames, so it is fixed here. Centre about (745, 412), radius
    /// about 253 px (the bright centroid is (747, 412)).
    private let circle = FieldCircle(centre: CGPoint(x: 745, y: 412), radius: 253)

    private var circleSquare: CGRect {
        CGRect(
            x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
            width: circle.radius * 2, height: circle.radius * 2)
    }

    private func frame(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "png"), "missing \(name)")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// A detection's box in frame pixels from the top left.
    private func pixels(_ detection: OrganismDetector.Detection) -> CGRect {
        OrganismTally.Found(detection, frameWidth: 1280, frameHeight: 720).box
    }

    /// What the live-count path keeps: the crop square to the detector, then the guards.
    private func liveCountSurvivors(
        _ name: String, detector: OrganismDetector
    ) throws -> (crop: CGRect, all: [OrganismDetector.Detection], kept: [OrganismDetector.Detection]) {
        let crop = FieldCentring.cropRect(for: circle, frameSize: frameSize)
        let all = try detector.detections(in: try frame(name), crop: crop)
        var counter = LiveOrganismCounter()
        let result = counter.update(
            detections: all, pictureMoved: .zero, trackerPosition: .zero, frameSize: frameSize,
            fieldCircle: circle, crop: crop, seconds: 0, column: 1)
        let guards = DetectionGuards()
        let kept = all.filter { guards.drop(box: pixels($0), crop: crop, circle: circle) == nil }
        XCTAssertEqual(result.found + result.outsideField, kept.count)
        return (crop, all, kept)
    }

    func testV2OpensAndNamesItsTwentyThreeClassesInOrder() throws {
        let started = CFAbsoluteTimeGetCurrent()
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        print("V2TEST open", Int((CFAbsoluteTimeGetCurrent() - started) * 1000), "ms")
        XCTAssertEqual(detector.kind, .v2)
        XCTAssertEqual(detector.modelName, "SoilDetectorV2")
        XCTAssertEqual(detector.classNames.count, 24, "background and 23 classes")
        XCTAssertEqual(detector.classNames.first, "background")
        XCTAssertEqual(detector.classNames[6], "Didinium_Phacus_Collodictyon")
        XCTAssertEqual(detector.classNames, DetectorModel.v2ClassNames, "metadata matches the built-in list")
        XCTAssertEqual(OrganismDetector.modelName, "SoilDetector", "V1's name is unchanged")
        // V1's package is no longer in the app, so the no-argument detector is not opened here.
        XCTAssertEqual(DetectorModel.v1.resourceName, OrganismDetector.modelName)
    }

    /// Documents the problem: this is expected to pass.
    func testWholeFrameV2BoxesTheEyepieceDisc() throws {
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        let found = try detector.detections(in: try frame("eyepiece-disc-030"))
        let overlaps = found.filter {
            DetectionGuards.iou(pixels($0), circleSquare) >= 0.5 && $0.confidence >= 0.3 - 0.0001
        }
        print("V2TEST disc whole frame", found.map { "\($0.label) \($0.confidence) \(pixels($0))" })
        XCTAssertFalse(overlaps.isEmpty, "V2 boxes the whole disc without a crop")
    }

    func testTheDiscIsGoneThroughTheLiveCountPath() throws {
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        let run = try liveCountSurvivors("eyepiece-disc-030", detector: detector)
        print(
            "V2TEST disc live", run.kept.map { "\($0.label) \($0.confidence) \(pixels($0))" },
            "of", run.all.count)
        for detection in run.kept {
            XCTAssertLessThan(DetectionGuards.iou(pixels(detection), circleSquare), 0.5)
        }
    }

    func testNoBoxCoversMoreThanHalfTheCropOnTheSampleBand() throws {
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        let run = try liveCountSurvivors("sample-band-140", detector: detector)
        print(
            "V2TEST band live", run.kept.map { "\($0.label) \($0.confidence) \(pixels($0))" },
            "of", run.all.map { "\($0.label) \($0.confidence) \(pixels($0))" })
        let cropArea = Double(run.crop.width * run.crop.height)
        for detection in run.kept {
            let box = pixels(detection)
            XCTAssertLessThanOrEqual(Double(box.width * box.height) / cropArea, 0.5)
        }
    }

    func testCroppedBoxesMapBackIntoTheEyepiecesSquare() throws {
        let detector = try OrganismDetector(model: .v2, computeUnits: .cpuAndGPU)
        for name in ["eyepiece-disc-030", "sample-band-140"] {
            let run = try liveCountSurvivors(name, detector: detector)
            for detection in run.kept {
                let box = pixels(detection)
                XCTAssertTrue(
                    circleSquare.insetBy(dx: -8, dy: -8).contains(CGPoint(x: box.midX, y: box.midY)),
                    "\(name): \(detection.label) at \(box)")
                XCTAssertTrue(run.crop.insetBy(dx: -1, dy: -1).contains(box), "\(name): inside the crop")
            }
        }
    }

    // MARK: Crop origin

    /// Proves the crop's origin convention without a model: `FieldCentring.cropRect` counts from
    /// the top left, Core Image from the bottom left, and `OrganismDetector.cropped` flips between
    /// them. A black 10 px square at (150, 10) from the TOP LEFT of a white 200 x 100 picture must
    /// land at (50, 10) from the top left of the crop (100, 0, 100, 100), and nowhere else.
    func testTheCropRectCountsFromTheTopLeftAndSoDoesTheCroppedPicture() throws {
        let width = 200
        let height = 100
        let marked = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        marked.setFillColor(gray: 1, alpha: 1)
        marked.fill(CGRect(x: 0, y: 0, width: width, height: height))
        marked.setFillColor(gray: 0, alpha: 1)
        // Core Graphics counts from the bottom left: 10 px from the top is y = 100 - 10 - 10.
        marked.fill(CGRect(x: 150, y: 80, width: 10, height: 10))
        let source = CIImage(cgImage: try XCTUnwrap(marked.makeImage()))
        let cropped = OrganismDetector.cropped(source, to: CGRect(x: 100, y: 0, width: 100, height: 100))
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 100, height: 100))

        let picture = try XCTUnwrap(CIContext().createCGImage(cropped, from: cropped.extent))
        let readback = try XCTUnwrap(
            CGContext(
                data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        readback.draw(picture, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let data = try XCTUnwrap(readback.data).assumingMemoryBound(to: UInt8.self)
        // Row 0 of a bitmap's memory is the top of the picture.
        var dark: [(x: Int, y: Int)] = []
        for y in 0..<100 {
            for x in 0..<100 where data[y * 400 + x * 4] < 128 { dark.append((x, y)) }
        }
        XCTAssertEqual(dark.count, 100)
        XCTAssertEqual(dark.map(\.x).min(), 50)
        XCTAssertEqual(dark.map(\.x).max(), 59)
        XCTAssertEqual(dark.map(\.y).min(), 10)
        XCTAssertEqual(dark.map(\.y).max(), 19)
    }
}
