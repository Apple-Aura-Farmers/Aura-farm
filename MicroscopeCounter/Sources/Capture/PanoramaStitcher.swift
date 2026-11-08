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
///
/// Two things here follow Akbar's write-up on stitching microscope images with OpenPano
/// (auriza.github.io/micro-stitch): frames are feathered together rather than pasted, with
/// the weight falling off vertically as well as horizontally, and a frame that will not
/// match is stepped over instead of ending the sweep.
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

    /// The most a frame may be judged to have moved, as a fraction of its own size. Past this
    /// two frames have too little in common for the match to be trusted, and registration
    /// does sometimes return a confident, badly wrong answer. A panorama with a frame pasted
    /// far out of place is worse than no panorama, so this is treated as a failure to line up
    /// rather than clamped or guessed at.
    ///
    /// Measured, on one photograph. Cutting a 4000x3013 photograph into the twelve
    /// overlapping fields a sweep walks and joining them back gives a known right answer for
    /// every frame. Stepping 0.42 of a frame between them, each of the twelve landed on the
    /// pixel it was cut from; at 0.44 and at 0.46 one pair came back 58 and 114 px wrong, and
    /// the frames after it carried that error. So the point where registration stops being
    /// trustworthy sits just above 0.42 on that picture, and this leaves a margin under it.
    ///
    /// NOT calibrated on a microscope. A star field is high-contrast points and a slide under
    /// a lens is not, so the number this was measured at may not carry over. It costs nothing
    /// on the footage to hand: of the eleven pairs in a sweep recorded through a microscope,
    /// the six that 0.5 admitted are all under 0.37, so tightening refused none of them.
    static let maxShiftFraction = 0.4

    /// Above this many pixels the frames are pasted rather than feathered, because
    /// feathering holds four floats per pixel of canvas: 8 megapixels is 128 MB of working
    /// memory, and the sweeps this app records come out at 2.9 to 4.7 megapixels.
    static let maxBlendPixels = 8_000_000

    /// Where each frame sits on the canvas, in pixels from its top-left corner, or nil for a
    /// frame that was left out. The first frame laid down is the origin, so offsets can be
    /// negative.
    ///
    /// Each frame is registered against the one before it. When a pair does not match, the
    /// frame after it is tried against the same anchor: if that one matches, the odd frame
    /// was a single bad frame and it is stepped over, and the run carries on. A sweep's rows
    /// overlap enough that skipping one frame still leaves the next within reach.
    ///
    /// Only when the frame after will not match either is the chain really broken, and the
    /// run ends there. The longest run is laid down and the rest left out: one frame pasted
    /// far out of place spoils the whole picture. Nothing is deleted, the frames are all
    /// still on disk.
    ///
    /// Stepping over the bad frame is what Akbar's write-up settles on after finding that
    /// abandoning everything downstream of a failure throws away most of a sweep: on one of
    /// its five sets, recovering this way cost 4 frames where giving up cost 13.
    static func offsets(for urls: [URL]) throws -> [CGPoint?] {
        guard urls.count >= 2 else { throw Failure.notEnoughFrames }

        var runs: [(indices: [Int], offsets: [CGPoint])] = [(indices: [0], offsets: [.zero])]
        var anchor = try load(urls[0])
        var index = 1

        while index < urls.count {
            let current = try load(urls[index])
            if let shift = contentShift(from: anchor, to: current),
                let last = runs[runs.count - 1].offsets.last
            {
                // The content moved by `shift` between the two frames, so this frame has to be
                // laid down that much further back for the content to line up again.
                runs[runs.count - 1].indices.append(index)
                runs[runs.count - 1].offsets.append(
                    CGPoint(x: last.x - shift.x, y: last.y - shift.y))
                anchor = current
                index += 1
                continue
            }

            // Is it this frame that is bad, or has the sweep really jumped? Ask the frame
            // after it, against the same anchor.
            if index + 1 < urls.count,
                let next = try? load(urls[index + 1]),
                let shift = contentShift(from: anchor, to: next),
                let last = runs[runs.count - 1].offsets.last
            {
                runs[runs.count - 1].indices.append(index + 1)
                runs[runs.count - 1].offsets.append(
                    CGPoint(x: last.x - shift.x, y: last.y - shift.y))
                anchor = next
                index += 2
                continue
            }

            runs.append((indices: [index], offsets: [.zero]))
            anchor = current
            index += 1
        }

        guard let longest = runs.max(by: { $0.offsets.count < $1.offsets.count }),
            longest.offsets.count >= 2
        else { throw Failure.nothingLinedUp }

        var placed = [CGPoint?](repeating: nil, count: urls.count)
        for (position, offset) in longest.offsets.enumerated() {
            placed[longest.indices[position]] = offset
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
    static func stitch(
        frameURLs: [URL],
        maxCanvasPixels: Int = defaultMaxCanvasPixels,
        maxBlendPixels: Int = maxBlendPixels
    ) throws -> Panorama {
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

        if width * height <= maxBlendPixels,
            let feathered = try feather(placed, width: width, height: height, canvas: frame)
        {
            return Panorama(image: feathered, framesLeftOut: frameURLs.count - placed.count)
        }

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

    /// Averages the frames together rather than letting the last one drawn win, weighting
    /// each pixel by how near the middle of its own frame it is. A pasted frame leaves a
    /// hard line wherever one ends and the next begins; this fades them into each other.
    ///
    /// The weight is OpenPano's, `(0.5 - |x/width - 0.5|)` across, but multiplied by the
    /// same falloff down the frame. OpenPano applies the vertical term only for unordered
    /// input, because it joins left to right; a sweep walks rows as well as columns, so the
    /// seams run both ways and both terms are always needed.
    ///
    /// Returns nil if the buffers could not be made, and the caller pastes instead.
    private static func feather(
        _ placed: [(url: URL, offset: CGPoint, size: CGSize)],
        width: Int, height: Int, canvas: CGRect
    ) throws -> CGImage? {
        let pixelCount = width * height
        var totals = [Float](repeating: 0, count: pixelCount * 3)
        var weights = [Float](repeating: 0, count: pixelCount)

        for item in placed {
            let image = try load(item.url)
            let frameWidth = image.width
            let frameHeight = image.height
            var pixels = [UInt8](repeating: 0, count: frameWidth * frameHeight * 4)
            guard
                let reader = CGContext(
                    data: &pixels, width: frameWidth, height: frameHeight, bitsPerComponent: 8,
                    bytesPerRow: frameWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            reader.draw(
                image, in: CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))

            // Both buffers count rows from the bottom, the way CGContext draws, so the
            // frame's place on the canvas is worked out the same way as when pasting.
            let left = Int((item.offset.x - canvas.minX).rounded())
            let top = item.offset.y - canvas.minY
            let bottom = Int((canvas.height - top - item.size.height).rounded())

            pixels.withUnsafeBufferPointer { source in
                totals.withUnsafeMutableBufferPointer { totals in
                    weights.withUnsafeMutableBufferPointer { weights in
                        for y in 0..<frameHeight {
                            let canvasY = bottom + y
                            guard canvasY >= 0, canvasY < height else { continue }
                            // Never quite zero, so a pixel only one frame reaches still
                            // divides back out to the colour that frame saw.
                            let down = max(
                                0.5 - abs(Float(y) / Float(frameHeight) - 0.5), 0.0001)
                            for x in 0..<frameWidth {
                                let canvasX = left + x
                                guard canvasX >= 0, canvasX < width else { continue }
                                let across = max(
                                    0.5 - abs(Float(x) / Float(frameWidth) - 0.5), 0.0001)
                                let weight = across * down
                                let from = (y * frameWidth + x) * 4
                                let into = canvasY * width + canvasX
                                totals[into * 3] += Float(source[from]) * weight
                                totals[into * 3 + 1] += Float(source[from + 1]) * weight
                                totals[into * 3 + 2] += Float(source[from + 2]) * weight
                                weights[into] += weight
                            }
                        }
                    }
                }
            }
        }

        var output = [UInt8](repeating: 0, count: pixelCount * 4)
        output.withUnsafeMutableBufferPointer { output in
            totals.withUnsafeBufferPointer { totals in
                weights.withUnsafeBufferPointer { weights in
                    for index in 0..<pixelCount {
                        let weight = weights[index]
                        // Canvas the frames never reached stays black, as it was when pasted.
                        guard weight > 0 else { continue }
                        for channel in 0..<3 {
                            let value = totals[index * 3 + channel] / weight
                            output[index * 4 + channel] = UInt8(
                                max(0, min(255, value.rounded())))
                        }
                    }
                }
            }
        }

        return output.withUnsafeMutableBytes { bytes -> CGImage? in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
    }

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
