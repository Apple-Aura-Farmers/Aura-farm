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
        /// No two frames in a row lined up, so there is nothing to join.
        case nothingLinedUp
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

    /// Where each frame sits on the canvas, in pixels from its top-left corner, or nil for a
    /// frame that was left out. The first frame laid down is the origin, so offsets can be
    /// negative.
    ///
    /// Each frame is registered against the one before it, so a pair that does not match breaks
    /// the chain. The longest unbroken run is laid down and the rest are left out: one frame
    /// pasted far out of place spoils the whole picture. Nothing is deleted, the frames are all
    /// still on disk.
    static func offsets(for urls: [URL]) throws -> [CGPoint?] {
        guard urls.count >= 2 else { throw Failure.notEnoughFrames }

        var runs: [(start: Int, offsets: [CGPoint])] = [(start: 0, offsets: [.zero])]
        var previous = try load(urls[0])

        for index in 1..<urls.count {
            let current = try load(urls[index])
            if let shift = contentShift(from: previous, to: current),
                let last = runs[runs.count - 1].offsets.last
            {
                // The content moved by `shift` between the two frames, so this frame has to be
                // laid down that much further back for the content to line up again.
                runs[runs.count - 1].offsets.append(
                    CGPoint(x: last.x - shift.x, y: last.y - shift.y))
            } else {
                runs.append((start: index, offsets: [.zero]))
            }
            previous = current
        }

        guard let longest = runs.max(by: { $0.offsets.count < $1.offsets.count }),
            longest.offsets.count >= 2
        else { throw Failure.nothingLinedUp }

        var placed = [CGPoint?](repeating: nil, count: urls.count)
        for (position, offset) in longest.offsets.enumerated() {
            placed[longest.start + position] = offset
        }
        return placed
    }

    /// A joined picture, and how many of the frames it was asked for did not make it in.
    struct Panorama {
        var image: CGImage
        var framesLeftOut: Int
    }

    /// Draws the frames onto one canvas. Later frames are drawn over earlier ones, so the
    /// newest look at a patch of slide wins where they overlap.
    static func stitch(frameURLs: [URL], maxCanvasPixels: Int = defaultMaxCanvasPixels) throws
        -> Panorama
    {
        let offsets = try offsets(for: frameURLs)
        var placed: [(url: URL, offset: CGPoint, size: CGSize)] = []
        for (index, url) in frameURLs.enumerated() {
            guard let offset = offsets[index] else { continue }
            let image = try load(url)
            placed.append(
                (url: url, offset: offset, size: CGSize(width: image.width, height: image.height)))
        }

        guard var frame = placed.first.map({ CGRect(origin: $0.offset, size: $0.size) }) else {
            throw Failure.nothingLinedUp
        }
        for item in placed.dropFirst() {
            frame = frame.union(CGRect(origin: item.offset, size: item.size))
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

        for item in placed {
            let image = try load(item.url)
            // Offsets are measured from the top-left; CGContext draws from the bottom-left.
            let left = item.offset.x - frame.minX
            let top = item.offset.y - frame.minY
            let bottom = frame.height - top - item.size.height
            context.draw(
                image,
                in: CGRect(x: left, y: bottom, width: item.size.width, height: item.size.height)
            )
        }

        guard let result = context.makeImage() else { throw Failure.couldNotDraw }
        return Panorama(image: result, framesLeftOut: frameURLs.count - placed.count)
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

    /// How far the picture moved between two frames, in pixels, or nil when the two do not
    /// have enough in common for the match to be trusted.
    private static func contentShift(from previous: CGImage, to current: CGImage) -> CGPoint? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previous)
        let handler = VNImageRequestHandler(cgImage: current)
        guard (try? handler.perform([request])) != nil,
            let observation = request.results?.first
        else { return nil }

        let transform = observation.alignmentTransform
        // Vision works bottom-up, these offsets are top-down, so the vertical shift flips.
        let shift = CGPoint(x: transform.tx, y: -transform.ty)

        guard abs(shift.x) <= Double(current.width) * maxShiftFraction,
            abs(shift.y) <= Double(current.height) * maxShiftFraction
        else { return nil }
        return shift
    }

    private static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.couldNotRead(url) }
        return image
    }
}
