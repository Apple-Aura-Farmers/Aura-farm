import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MicroscopeCounter

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
        assertEqual(panorama.width, frameWidth + 2 * step, accuracy: 2)
        assertEqual(panorama.height, frameHeight, accuracy: 2)

        let expected = try XCTUnwrap(
            source.cropping(to: CGRect(x: 0, y: 0, width: panorama.width, height: panorama.height)))
        assertLooksTheSame(panorama, expected)
    }

    func testOffsetsStepAlongByTheDistanceTheWindowMoved() throws {
        let source = makeTexturedImage(width: 400, height: frameHeight)
        let urls = try write(windows: [0, step, 2 * step], of: source)

        let offsets = try PanoramaStitcher.offsets(for: urls)

        XCTAssertEqual(offsets.count, 3)
        XCTAssertEqual(offsets[0], .zero)
        XCTAssertEqual(offsets[1].x, Double(step), accuracy: 2)
        XCTAssertEqual(offsets[2].x, Double(2 * step), accuracy: 2)
        // The window only moved sideways, so nothing should have drifted up or down.
        XCTAssertEqual(offsets[1].y, 0, accuracy: 2)
        XCTAssertEqual(offsets[2].y, 0, accuracy: 2)
    }

    func testFramesThatShareTooLittleAreNotForcedTogether() throws {
        // Two windows with no overlap at all: whatever registration returns, it is not a match.
        let source = makeTexturedImage(width: 800, height: frameHeight)
        let urls = try write(windows: [0, 600], of: source)

        XCTAssertThrowsError(try PanoramaStitcher.stitch(frameURLs: urls)) { error in
            XCTAssertEqual(error as? PanoramaStitcher.Failure, .couldNotLineUp(frame: 1))
        }
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
