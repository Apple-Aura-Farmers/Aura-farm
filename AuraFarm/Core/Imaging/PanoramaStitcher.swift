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

    /// How well two frames must agree on the ground they share before the shift between them
    /// is believed. `maxShiftFraction` cannot catch a wrong answer that reports an ordinary
    /// shift; this can, because it looks at the frames rather than at the number.
    ///
    /// Measured on the twelve fields cut from one photograph and on a twelve frame sweep
    /// recorded through a microscope. Every pair that was really the same ground scored 0.63
    /// or better, down to 0.63 on a field with almost nothing in it; every wrong answer
    /// scored 0.41 or worse, including one that reported a shift of a tenth of a frame and
    /// was 104 px out. This sits between them with room either side.
    ///
    /// It refuses an honest answer on a frame with too little in it to correlate, and that is
    /// the intent: a shift nothing in the picture supports is a guess, and a frame pasted on
    /// a guess is worse than a frame left out.
    static let leastAgreement = 0.5

    /// How far from registration's answer to look for a shift the frames do agree on, in
    /// pixels. The misses worth correcting are near misses: on the sweep to hand the one
    /// wrong answer was 104 px out, and on the photograph 58 px. An answer further out than
    /// this is not a near miss but a pair that does not belong together.
    static let searchReach = 150.0

    /// The search looks over eighth-size copies first. A 1080 px frame comes down to 135 px,
    /// which still carries the grit and debris the match turns on, and makes a search over
    /// 1369 shifts a few hundredths of a second instead of several seconds.
    static let coarseScale = 8

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

        // Registration answers with a shift and no word on whether it means it, so the answer
        // is checked against the frames themselves. The frame moved the other way from the
        // picture inside it.
        guard let first = Grey(previous), let second = Grey(current) else { return nil }
        if first.agreement(with: second, movedBy: CGPoint(x: -shift.x, y: -shift.y))
            >= leastAgreement
        {
            return shift
        }

        // Confident and wrong. The shift the frames do agree on is usually close by, so it is
        // worth looking before giving the frame up.
        return shiftNearby(shift, between: first, and: second)
    }

    /// Looks for a shift the two frames agree on, around the one registration gave. Returns
    /// nil when the best it can find is still not agreement.
    ///
    /// Searched around registration's answer rather than over everything: an answer a whole
    /// field out is not a near miss to be nudged into place but a pair that does not belong
    /// together, and leaving it out is the right end for it.
    ///
    /// Coarse then fine. Eighth-size copies carry enough to find the right neighbourhood for
    /// a few hundred thousand comparisons, and the answer is then settled a pixel at a time
    /// at full size, since a frame laid down eight pixels out still shows at the seam.
    ///
    /// Only shifts inside `maxShiftFraction` are tried. That is not only the same rule the
    /// caller applies: trying hundreds of shifts means hundreds of chances to land on a
    /// spurious agreement, and a shift that leaves the two frames sharing a sliver is where
    /// one is found. Holding the search to shifts that leave most of the frame shared is
    /// what keeps it from talking itself into a match.
    static func shiftNearby(_ proposed: CGPoint, between first: Grey, and second: Grey)
        -> CGPoint?
    {
        guard let coarseFirst = first.scaledDown(by: coarseScale),
            let coarseSecond = second.scaledDown(by: coarseScale)
        else { return nil }
        let furthestX = Double(second.width) * maxShiftFraction
        let furthestY = Double(second.height) * maxShiftFraction
        func allowed(x: Int, y: Int) -> Bool {
            Double(abs(x)) <= furthestX && Double(abs(y)) <= furthestY
        }

        let from = CGPoint(x: -proposed.x, y: -proposed.y)
        let reach = Int(searchReach) / coarseScale
        let centreX = Int(from.x.rounded()) / coarseScale
        let centreY = Int(from.y.rounded()) / coarseScale
        var best = (score: -2.0, x: 0, y: 0)
        for y in (centreY - reach)...(centreY + reach) {
            for x in (centreX - reach)...(centreX + reach)
            where allowed(x: x * coarseScale, y: y * coarseScale) {
                let score = coarseFirst.agreement(
                    with: coarseSecond, movedBy: CGPoint(x: x, y: y), sampling: 1)
                if score > best.score { best = (score, x * coarseScale, y * coarseScale) }
            }
        }
        guard best.score > -2 else { return nil }

        var settled = (score: -2.0, x: best.x, y: best.y)
        for y in (best.y - coarseScale)...(best.y + coarseScale) {
            for x in (best.x - coarseScale)...(best.x + coarseScale) where allowed(x: x, y: y) {
                let score = first.agreement(with: second, movedBy: CGPoint(x: x, y: y))
                if score > settled.score { settled = (score, x, y) }
            }
        }
        guard settled.score >= leastAgreement else { return nil }
        // Back to how the picture moved, which is what the caller works in.
        return CGPoint(x: -Double(settled.x), y: -Double(settled.y))
    }

    /// How closely two frames agree on the ground they share, once one is moved onto the
    /// other. See `Grey.agreement(with:movedBy:sampling:)`.
    static func agreement(between previous: CGImage, and current: CGImage, movedBy: CGPoint)
        -> Double
    {
        guard let first = Grey(previous), let second = Grey(current) else { return 0 }
        return first.agreement(with: second, movedBy: movedBy)
    }

    /// A frame as one grey value per pixel, which is all that comparing two of them needs.
    /// Kept rather than drawn each time, because the search tries hundreds of shifts.
    struct Grey {
        var pixels: [UInt8]
        var width: Int
        var height: Int

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            pixels = [UInt8](repeating: 0, count: width * height)
            guard draw(image) else { return nil }
        }

        private init(pixels: [UInt8], width: Int, height: Int) {
            self.pixels = pixels
            self.width = width
            self.height = height
        }

        private mutating func draw(_ image: CGImage) -> Bool {
            let size = CGRect(x: 0, y: 0, width: width, height: height)
            let drawnWidth = width
            let drawnHeight = height
            return pixels.withUnsafeMutableBytes { bytes -> Bool in
                guard
                    let context = CGContext(
                        data: bytes.baseAddress, width: drawnWidth, height: drawnHeight,
                        bitsPerComponent: 8, bytesPerRow: drawnWidth,
                        space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: size)
                return true
            }
        }

        /// Every `factor`th pixel, averaged over the square it stands for, so a feature
        /// smaller than the square still leaves a mark on the smaller copy.
        func scaledDown(by factor: Int) -> Grey? {
            let small = (width: width / factor, height: height / factor)
            guard small.width > 8, small.height > 8 else { return nil }
            var buffer = [UInt8](repeating: 0, count: small.width * small.height)
            for y in 0..<small.height {
                for x in 0..<small.width {
                    var total = 0
                    for innerY in 0..<factor {
                        let row = (y * factor + innerY) * width + x * factor
                        for innerX in 0..<factor { total += Int(pixels[row + innerX]) }
                    }
                    buffer[y * small.width + x] = UInt8(total / (factor * factor))
                }
            }
            return Grey(pixels: buffer, width: small.width, height: small.height)
        }

        /// 1 is the same ground seen twice, 0 is unrelated, and below 0 they disagree.
        /// Normalised, so one frame being brighter or flatter than the other does not count
        /// against it.
        ///
        /// `sampling` is how many pixels to step between samples. The answer is a correlation
        /// over the whole shared area, so leaving fifteen pixels in sixteen out of it changes
        /// the figure in the third decimal and makes the check cost a few milliseconds.
        func agreement(with other: Grey, movedBy: CGPoint, sampling: Int = 4) -> Double {
            let dx = Int(movedBy.x.rounded())
            let dy = Int(movedBy.y.rounded())
            // The part of `other` that lands on this one once it is moved.
            let left = max(0, dx)
            let right = min(width, other.width + dx)
            let top = max(0, dy)
            let bottom = min(height, other.height + dy)
            guard right - left > 8, bottom - top > 8 else { return -2 }

            var sumFirst = 0.0
            var sumSecond = 0.0
            var squaresFirst = 0.0
            var squaresSecond = 0.0
            var products = 0.0
            var count = 0.0
            for y in stride(from: top, to: bottom, by: sampling) {
                for x in stride(from: left, to: right, by: sampling) {
                    let a = Double(pixels[y * width + x])
                    let b = Double(other.pixels[(y - dy) * other.width + (x - dx)])
                    sumFirst += a
                    sumSecond += b
                    squaresFirst += a * a
                    squaresSecond += b * b
                    products += a * b
                    count += 1
                }
            }
            guard count > 64 else { return -2 }

            let covariance = products / count - (sumFirst / count) * (sumSecond / count)
            let spreadFirst = squaresFirst / count - (sumFirst / count) * (sumFirst / count)
            let spreadSecond = squaresSecond / count - (sumSecond / count) * (sumSecond / count)
            // A frame of one flat colour correlates with nothing, itself included.
            guard spreadFirst > 0.0001, spreadSecond > 0.0001 else { return -2 }
            return covariance / (spreadFirst * spreadSecond).squareRoot()
        }
    }

    private static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.couldNotRead(url) }
        return image
    }
}
