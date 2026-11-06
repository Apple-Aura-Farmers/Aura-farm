import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AuraFarm

/// Builds frames by cutting windows out of one wide picture, so the panorama that lines them
/// up again can be compared against the picture they came from.
final class PanoramaStitcherTests: XCTestCase {
    private let frameWidth = 200
    private let frameHeight = 150
    private let step = 60

    func testFramesAreLinedUpBackIntoThePictureTheyCameFrom() throws {
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0, step, 2 * step], of: source)

        let panorama = try PanoramaStitcher.stitch(frameURLs: urls)

        // Three windows a step apart cover the first frame plus two steps of new ground.
        assertEqual(panorama.image.width, frameWidth + 2 * step, accuracy: 2)
        assertEqual(panorama.image.height, frameHeight, accuracy: 2)
        XCTAssertEqual(panorama.framesLeftOut, 0)

        let expected = try XCTUnwrap(
            source.cropping(
                to: CGRect(
                    x: 0, y: 0, width: panorama.image.width, height: panorama.image.height)))
        assertLooksTheSame(panorama.image, expected)
    }

    func testOffsetsStepAlongByTheDistanceTheWindowMoved() throws {
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0, step, 2 * step], of: source)

        let offsets = try PanoramaStitcher.offsets(for: urls)

        XCTAssertEqual(offsets.count, 3)
        XCTAssertEqual(try XCTUnwrap(offsets[0]), .zero)
        XCTAssertEqual(try XCTUnwrap(offsets[1]).x, Double(step), accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(offsets[2]).x, Double(2 * step), accuracy: 2)
        // The window only moved sideways, so nothing should have drifted up or down.
        XCTAssertEqual(try XCTUnwrap(offsets[1]).y, 0, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(offsets[2]).y, 0, accuracy: 2)
    }

    func testFramesThatShareTooLittleAreNotForcedTogether() throws {
        // Two windows with no overlap at all: whatever registration returns, it is not a match.
        let source = makeTexturedImage(width: 800, height: frameHeight)
        let urls = try write(windows: [0, 600], of: source)

        XCTAssertThrowsError(try PanoramaStitcher.stitch(frameURLs: urls)) { error in
            XCTAssertEqual(error as? PanoramaStitcher.Failure, .nothingLinedUp)
        }
    }

    func testAFrameFromSomewhereElseIsLeftOutInsteadOfSpoilingThePicture() throws {
        // What real footage does: the first frame is from before the sweep started, and the
        // rest are a steady pan. The odd one out should not cost the other three.
        let source = makeTexturedImage(width: 800, height: frameHeight)
        let urls = try write(windows: [600, 0, step, 2 * step], of: source)

        let panorama = try PanoramaStitcher.stitch(frameURLs: urls)

        XCTAssertEqual(panorama.framesLeftOut, 1)
        assertEqual(panorama.image.width, frameWidth + 2 * step, accuracy: 2)

        let offsets = try PanoramaStitcher.offsets(for: urls)
        XCTAssertNil(offsets[0])
        XCTAssertEqual(try XCTUnwrap(offsets[1]), .zero)
        XCTAssertEqual(try XCTUnwrap(offsets[3]).x, Double(2 * step), accuracy: 2)
    }

    func testASingleBadFrameIsSteppedOverRatherThanEndingTheSweep() throws {
        // A steady pan with one frame from elsewhere dropped into the middle of it. Giving
        // up at the break would cost every frame after it; the run should carry on.
        // The windows start at 180 because the generated texture is too sparse for
        // registration around x = 120, which would fail the pan for its own reasons.
        let first = 180
        let source = makeTexturedImage(width: 900, height: frameHeight)
        let urls = try write(
            windows: [first, first + step, 700, first + 2 * step, first + 3 * step], of: source)

        let offsets = try PanoramaStitcher.offsets(for: urls)

        XCTAssertNil(offsets[2], "the odd frame should be the one left out")
        XCTAssertEqual(try XCTUnwrap(offsets[0]), .zero)
        XCTAssertEqual(try XCTUnwrap(offsets[1]).x, Double(step), accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(offsets[3]).x, Double(2 * step), accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(offsets[4]).x, Double(3 * step), accuracy: 2)
    }

    func testTheSeamBetweenTwoFramesIsFadedRatherThanCut() throws {
        // Two windows overlapping by most of their width. Pasting leaves a step in
        // brightness down the line where the second frame starts; feathering should not.
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0, step], of: source)

        let panorama = try PanoramaStitcher.stitch(frameURLs: urls)
        let expected = try XCTUnwrap(
            source.cropping(
                to: CGRect(
                    x: 0, y: 0, width: panorama.image.width, height: panorama.image.height)))
        // Feathering averages two views of the same slide, so it has to stay faithful to it.
        assertLooksTheSame(panorama.image, expected)

        // Walk the columns and find the biggest jump from one to the next. A hard seam shows
        // up as one column stepping away from its neighbour far more than the texture does.
        let columns = columnMeans(of: panorama.image)
        let biggestStep = zip(columns, columns.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(biggestStep, 12, "a seam this sharp means the frames were pasted")
    }

    func testAnEnormousCanvasIsPastedRatherThanFeathered() throws {
        // Feathering holds four floats a pixel, so past the cap it has to fall back. The
        // picture still has to come out right.
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0, step, 2 * step], of: source)

        let feathered = try PanoramaStitcher.stitch(frameURLs: urls)
        let pasted = try PanoramaStitcher.stitch(frameURLs: urls, maxBlendPixels: 0)

        XCTAssertEqual(feathered.image.width, pasted.image.width)
        XCTAssertEqual(feathered.image.height, pasted.image.height)
        assertLooksTheSame(pasted.image, feathered.image)
    }

    func testOneFrameIsNotAPanorama() throws {
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0], of: source)

        XCTAssertThrowsError(try PanoramaStitcher.stitch(frameURLs: urls)) { error in
            XCTAssertEqual(error as? PanoramaStitcher.Failure, .notEnoughFrames)
        }
    }

    func testACanvasThatWouldBeAbsurdIsRefused() throws {
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0, step], of: source)

        XCTAssertThrowsError(try PanoramaStitcher.stitch(frameURLs: urls, maxCanvasPixels: 100)) {
            error in
            guard case .tooLarge = error as? PanoramaStitcher.Failure else {
                return XCTFail("expected tooLarge, got \(error)")
            }
        }
    }

    func testAMissingFrameIsReported() {
        let missing = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
        XCTAssertThrowsError(try PanoramaStitcher.stitch(frameURLs: [missing, missing])) { error in
            XCTAssertEqual(error as? PanoramaStitcher.Failure, .couldNotRead(missing))
        }
    }

    // MARK: Helpers

    /// Blobs at fixed positions: registration needs something to lock onto, and a fixed
    /// layout keeps the test from depending on a random seed.
    private func makeTexturedImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.15, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var value = 7
        for _ in 0..<160 {
            value = (value &* 1_103_515_245 &+ 12_345) & 0x7FFF_FFFF
            let x = Double(value % width)
            let y = Double((value / 97) % height)
            let size = Double((value / 13) % 9) + 3
            context.setFillColor(CGColor(gray: Double((value / 7) % 100) / 100, alpha: 1))
            context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
        return context.makeImage()!
    }

    private func write(windows: [Int], of source: CGImage) throws -> [URL] {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

        return try windows.enumerated().map { index, x in
            let window = try XCTUnwrap(
                source.cropping(
                    to: CGRect(x: x, y: 0, width: frameWidth, height: frameHeight)))
            let url = folder.appending(path: String(format: "frame_%02d.jpg", index + 1))
            // Lossless, so a JPEG artefact cannot be mistaken for a registration error.
            let destination = try XCTUnwrap(
                CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, window, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return url
        }
    }

    private func assertLooksTheSame(
        _ image: CGImage, _ expected: CGImage, file: StaticString = #filePath, line: UInt = #line
    ) {
        let a = grayPixels(of: image)
        let b = grayPixels(of: expected)
        XCTAssertEqual(a.count, b.count, "sizes differ", file: file, line: line)
        guard a.count == b.count, !a.isEmpty else { return }

        let difference =
            zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
        // JPEG is out of the way, so anything beyond a few levels means the frames were laid
        // down in the wrong place.
        XCTAssertLessThan(difference, 6, "average pixel difference", file: file, line: line)
    }

    /// The mean grey of each column, for spotting a seam running down the picture.
    private func columnMeans(of image: CGImage) -> [Double] {
        let pixels = grayPixels(of: image)
        return (0..<image.width).map { x in
            var total = 0.0
            for y in 0..<image.height { total += Double(pixels[y * image.width + x]) }
            return total / Double(image.height)
        }
    }

    private func grayPixels(of image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}

/// XCTAssertEqual has no tolerance for Int, and registration lands a pixel or two out.
private func assertEqual(
    _ actual: Int, _ expected: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertLessThanOrEqual(
        abs(actual - expected), accuracy, "\(actual) is not within \(accuracy) of \(expected)",
        file: file, line: line)
}
