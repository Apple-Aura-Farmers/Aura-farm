import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Joins a sweep's frames into one wide image, the way a panorama does.
///
/// The slide travels on a flat stage, so frame to frame there is a shift and nothing else:
/// no rotation, no perspective. That makes translational registration the whole job, and it
/// is the same Vision request the shake estimate already uses.
///
/// The panorama is a derived file. The frames it is built from are the raw data and are
/// never edited or deleted to make it.
enum PanoramaStitcher {
    enum Failure: Error, Equatable {
        case notEnoughFrames
        case couldNotRead(URL)
        /// Registration failed between this frame and the one before it.
        case couldNotLineUp(frame: Int)
        /// The frames drifted so far apart that the canvas would be unreasonable.
        case tooLarge(pixels: Int)
        case couldNotDraw
    }

    /// Roughly 40 megapixels, which a dozen 720p frames stay well inside unless registration
    /// has drifted badly.
    static let defaultMaxCanvasPixels = 40_000_000

    /// The most a frame may be judged to have moved, as a fraction of its own size. Two frames
    /// that share less than half their area have too little in common for the match to be
    /// trusted, and registration does sometimes return a confident, badly wrong answer. A
    /// panorama with a frame pasted far out of place is worse than no panorama, so this is
    /// treated as a failure to line up rather than clamped or guessed at.
    static let maxShiftFraction = 0.5

    /// Where each frame sits on the canvas, in pixels from its top-left corner.
    /// The first frame is the origin, so offsets can be negative.
    static func offsets(for urls: [URL]) throws -> [CGPoint] {
        guard urls.count >= 2 else { throw Failure.notEnoughFrames }

        var offsets: [CGPoint] = [.zero]
        var previous = try load(urls[0])

        for index in 1..<urls.count {
            let current = try load(urls[index])
            let shift = try contentShift(from: previous, to: current, frame: index)
            // The content moved by `shift` between the two frames, so this frame has to be
            // laid down that much further back for the content to line up again.
            let last = offsets[index - 1]
            offsets.append(CGPoint(x: last.x - shift.x, y: last.y - shift.y))
            previous = current
        }
        return offsets
    }

    /// Draws the frames onto one canvas. Later frames are drawn over earlier ones, so the
    /// newest look at a patch of slide wins where they overlap.
    static func stitch(frameURLs: [URL], maxCanvasPixels: Int = defaultMaxCanvasPixels) throws
        -> CGImage
    {
        let offsets = try offsets(for: frameURLs)
        var sizes: [CGSize] = []
        for url in frameURLs {
            let image = try load(url)
            sizes.append(CGSize(width: image.width, height: image.height))
        }

        var frame = CGRect(origin: offsets[0], size: sizes[0])
        for index in 1..<offsets.count {
            frame = frame.union(CGRect(origin: offsets[index], size: sizes[index]))
        }

        let width = Int(frame.width.rounded(.up))
        let height = Int(frame.height.rounded(.up))
        guard width > 0, height > 0, width * height <= maxCanvasPixels else {
            throw Failure.tooLarge(pixels: max(width * height, 0))
        }

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw Failure.couldNotDraw }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (index, url) in frameURLs.enumerated() {
            let image = try load(url)
            // Offsets are measured from the top-left; CGContext draws from the bottom-left.
            let left = offsets[index].x - frame.minX
            let top = offsets[index].y - frame.minY
            let bottom = frame.height - top - sizes[index].height
            context.draw(
                image,
                in: CGRect(x: left, y: bottom, width: sizes[index].width, height: sizes[index].height)
            )
        }

        guard let result = context.makeImage() else { throw Failure.couldNotDraw }
        return result
    }

    /// Writes the panorama as a JPEG. Returns its size in bytes.
    @discardableResult
    static func write(_ image: CGImage, to url: URL, quality: Double = 0.85) throws -> Int {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { throw Failure.couldNotDraw }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.couldNotDraw }
        return (try? Data(contentsOf: url).count) ?? 0
    }

    // MARK: Private

    /// How far the picture moved between two frames, in pixels.
    private static func contentShift(from previous: CGImage, to current: CGImage, frame: Int) throws
        -> CGPoint
    {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previous)
        let handler = VNImageRequestHandler(cgImage: current)
        do {
            try handler.perform([request])
        } catch {
            throw Failure.couldNotLineUp(frame: frame)
        }
        guard let observation = request.results?.first else {
            throw Failure.couldNotLineUp(frame: frame)
        }

        let transform = observation.alignmentTransform
        // Vision works bottom-up, these offsets are top-down, so the vertical shift flips.
        let shift = CGPoint(x: transform.tx, y: -transform.ty)

        guard abs(shift.x) <= Double(current.width) * maxShiftFraction,
            abs(shift.y) <= Double(current.height) * maxShiftFraction
        else { throw Failure.couldNotLineUp(frame: frame) }
        return shift
    }

    private static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.couldNotRead(url) }
        return image
    }
}
