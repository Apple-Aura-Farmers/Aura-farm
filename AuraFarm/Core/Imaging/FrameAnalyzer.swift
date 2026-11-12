import CoreImage
import CoreVideo
import Foundation
import Vision

/// What one frame's luma says about it.
///
/// `contrast` is the standard deviation of the same downsampled luma values the
/// brightness is the mean of, on the 0...255 scale.
///
/// Blank glass is expected to have low contrast AND low sharpness, while blur should keep
/// some contrast with low sharpness. Both are hypotheses the slide movement lab is built
/// to test; nothing here relies on them yet.
struct FrameStats: Equatable {
    var brightness: Double
    var sharpness: Double
    var contrast: Double
}

/// Measures brightness and sharpness from the luma (Y) plane of a camera frame.
/// Expects a bi-planar YUV pixel buffer (420YpCbCr8BiPlanar).
enum FrameAnalyzer {
    /// - Parameter step: sample every Nth pixel in each direction to keep this cheap.
    ///   Sharpness is therefore measured at a coarser scale than the full frame.
    static func brightnessAndSharpness(
        of pixelBuffer: CVPixelBuffer,
        step: Int = 2
    ) -> (brightness: Double, sharpness: Double)? {
        guard let stats = stats(of: pixelBuffer, step: step) else { return nil }
        return (stats.brightness, stats.sharpness)
    }

    /// Brightness, sharpness and contrast in one pass over the luma plane.
    /// - Parameter step: as for `brightnessAndSharpness`.
    static func stats(of pixelBuffer: CVPixelBuffer, step: Int = 2) -> FrameStats? {
        stats(of: pixelBuffer, region: nil, step: step)
    }

    /// The same three numbers measured only inside `box`, given in full-frame pixels with the
    /// origin at the top left. The box is rounded to whole pixels and kept inside the frame.
    /// The eyepiece's dark ring is left out, which the whole-frame numbers cannot do: their
    /// contrast is dominated by bright field against black ring, so blank glass scores
    /// highest.
    static func stats(of pixelBuffer: CVPixelBuffer, in box: CGRect, step: Int) -> FrameStats? {
        stats(of: pixelBuffer, region: box, step: step)
    }

    private static func stats(of pixelBuffer: CVPixelBuffer, region: CGRect?, step: Int) -> FrameStats? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else { return nil }

        let fullWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let fullHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var originX = 0
        var originY = 0
        var width = fullWidth
        var height = fullHeight
        if let region {
            let minX = max(Int(region.minX.rounded()), 0)
            let minY = max(Int(region.minY.rounded()), 0)
            let maxX = min(Int(region.maxX.rounded()), fullWidth)
            let maxY = min(Int(region.maxY.rounded()), fullHeight)
            guard maxX > minX, maxY > minY else { return nil }
            originX = minX
            originY = minY
            width = maxX - minX
            height = maxY - minY
        }

        let w = width / step
        let h = height / step
        guard w > 2, h > 2 else { return nil }

        // Downsampled copy of the luma plane.
        var grid = [Float](repeating: 0, count: w * h)
        var sum = 0.0
        var squares = 0.0
        for y in 0..<h {
            let row = pixels + (originY + y * step) * bytesPerRow + originX
            for x in 0..<w {
                let value = Float(row[x * step])
                grid[y * w + x] = value
                sum += Double(value)
                squares += Double(value) * Double(value)
            }
        }
        let brightness = sum / Double(w * h)
        let contrast = max(squares / Double(w * h) - brightness * brightness, 0).squareRoot()

        // Variance of the 4-neighbour Laplacian: low values mean few sharp edges.
        var lapSum = 0.0
        var lapSquares = 0.0
        var count = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let lap = Double(4 * grid[i] - grid[i - 1] - grid[i + 1] - grid[i - w] - grid[i + w])
                lapSum += lap
                lapSquares += lap * lap
                count += 1
            }
        }
        let mean = lapSum / count
        let sharpness = lapSquares / count - mean * mean

        return FrameStats(brightness: brightness, sharpness: sharpness, contrast: contrast)
    }
}

/// Estimates camera shake as the average frame-to-frame shift over the last few analyzed frames.
/// Keeps one previous frame at most.
///
/// It also reports the last shift with its direction. Shake only needs a distance, but working
/// out how far the slide has actually travelled needs the direction too: a slide pushed back
/// and forth covers a lot of distance and no new ground.
final class ShakeEstimator {
    /// The last frame-to-frame shift, with direction, in pixels. nil until two frames have
    /// been compared.
    private(set) var lastShift: CGPoint?

    /// Where to register, as a Vision region: normalised, origin at the bottom left. nil is
    /// the whole frame, as it always was. It applies to the frame the request runs on (the
    /// newer one); the previous frame is kept whole. Used to stay inside an eyepiece's round
    /// field, whose static black ring would otherwise pin the answer at about 0 px.
    var regionOfInterest: CGRect?

    private let handler = VNSequenceRequestHandler()
    private var previous: CVPixelBuffer?
    private var recent: [Double] = []
    private let windowSize: Int

    init(windowSize: Int = 4) {
        self.windowSize = windowSize
    }

    /// Returns the average shift in pixels, or nil until two frames have been compared.
    func update(with buffer: CVPixelBuffer) -> Double? {
        defer { previous = buffer }
        lastShift = nil
        guard let previous else { return nil }

        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: previous)
        if let regionOfInterest { request.regionOfInterest = regionOfInterest }
        do {
            try handler.perform([request], on: buffer)
        } catch {
            return nil
        }
        guard let observation = request.results?.first else {
            return nil
        }

        let transform = observation.alignmentTransform
        // Vision works bottom-up and the rest of this app works top-down, so the vertical
        // shift flips, matching PanoramaStitcher.
        lastShift = CGPoint(x: transform.tx, y: -transform.ty)

        let shift = hypot(transform.tx, transform.ty)
        recent.append(Double(shift))
        if recent.count > windowSize { recent.removeFirst() }
        return recent.reduce(0, +) / Double(recent.count)
    }

    func reset() {
        previous = nil
        recent = []
        lastShift = nil
    }
}

/// How far the view has travelled from the frame the sweep last kept, in pixels.
///
/// A running total of frame-to-frame shifts cannot do this job. Measured against a held
/// frame on microscope footage, a view that had really moved 864 px had summed 5305 px of
/// frame-to-frame readings, so a threshold on the total fires at no particular distance.
/// This measures the one pair that matters, which is also the pair the stitcher will have to
/// line up.
///
/// Each measurement gets a `VNSequenceRequestHandler` of its own. A handler reused across
/// measurements against the same held frame reads 1 px every time, whatever has happened: on
/// 600 frames of microscope footage a reused handler never read above 1 px, where a fresh one
/// read a median of 305 px between kept frames. A sequence handler expects to be fed a
/// sequence, and a frame held still for several measurements is not one.
final class TravelSinceLastFrame {
    private var held: CVPixelBuffer?

    /// Where to register, as a Vision region: normalised, origin at the bottom left. nil is
    /// the whole frame, as it always was. It applies to the frame the request runs on (the
    /// newer one); the held frame is kept whole. See `ShakeEstimator.regionOfInterest`.
    var regionOfInterest: CGRect?

    /// The distance from the held frame, or nil when no frame is held yet or the two no
    /// longer have enough in common to be lined up at all.
    func distance(to buffer: CVPixelBuffer) -> Double? {
        offset(to: buffer).map { hypot($0.x, $0.y) }
    }

    /// The signed shift from the held frame, in pixels, x to the right and y down: the same
    /// registration as `distance(to:)`, with the vertical flipped the way `ShakeEstimator`
    /// flips it, because Vision works bottom-up. It is the move that puts this frame back on
    /// the held one, so content on the slide has gone the other way (see
    /// `CaptureViewModel.pictureMoved`).
    func offset(to buffer: CVPixelBuffer) -> CGPoint? {
        guard let held else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: held)
        if let regionOfInterest { request.regionOfInterest = regionOfInterest }
        guard (try? VNSequenceRequestHandler().perform([request], on: buffer)) != nil,
            let observation = request.results?.first
        else { return nil }
        let transform = observation.alignmentTransform
        return CGPoint(x: transform.tx, y: -transform.ty)
    }

    /// Call with every frame the sweep keeps: travel is measured from the last of them.
    func hold(_ buffer: CVPixelBuffer) {
        held = buffer
    }

    func reset() {
        held = nil
    }
}

/// Registers a box of one frame against the same box of another: BOTH are cropped to the same
/// rectangle before Vision sees them.
///
/// `regionOfInterest` only crops the newer frame (the frame the request runs on), so the held
/// frame is matched whole, eyepiece ring and all, and a box can be matched against the wrong
/// part of it. Hand-moved tests showed single readings jumping to about 250 px with the
/// frame-to-frame shift at 1 to 16 px. Cropping both compares like with like.
///
/// Each call gets a fresh request handler, for the reason `TravelSinceLastFrame` documents.
/// It holds nothing between calls: the crops are lazy images over the caller's buffers.
final class BoxRegistration {
    /// The least box side, in px, worth registering.
    private static let minimumSide: CGFloat = 16

    /// The signed shift from `held` to `current` inside `box` (full-frame pixels, origin at
    /// the top left), x to the right and y down: the same convention as
    /// `TravelSinceLastFrame.offset(to:)`. nil when the box is too small or Vision gives
    /// nothing.
    func offset(from held: CVPixelBuffer, to current: CVPixelBuffer, box: CGRect) -> CGPoint? {
        guard let rect = Self.wholePixelRect(of: box, in: current) else { return nil }
        return register(target: Self.crop(held, to: rect), on: Self.crop(current, to: rect))
    }

    /// The same, with the held picture a stored copy of the box (see `copy(of:box:context:)`)
    /// rather than a camera buffer: x to the right and y down, from the stored picture to
    /// `current`. nil when the stored picture is not the size of the box now.
    func offset(fromStored stored: CGImage, to current: CVPixelBuffer, box: CGRect) -> CGPoint? {
        guard let rect = Self.wholePixelRect(of: box, in: current),
            stored.width == Int(rect.width), stored.height == Int(rect.height)
        else { return nil }
        return register(target: CIImage(cgImage: stored), on: Self.crop(current, to: rect))
    }

    /// A deep copy of the box, rendered to an image of its own. It holds no reference to the
    /// camera's buffer, which must be given back to the capture pool.
    func copy(of buffer: CVPixelBuffer, box: CGRect, context: CIContext) -> CGImage? {
        guard let rect = Self.wholePixelRect(of: box, in: buffer) else { return nil }
        let cropped = Self.crop(buffer, to: rect)
        return context.createCGImage(cropped, from: cropped.extent)
    }

    /// The box in whole pixels, kept inside the frame; nil when it is too small to register.
    private static func wholePixelRect(of box: CGRect, in buffer: CVPixelBuffer) -> CGRect? {
        let bounds = CGRect(
            x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let whole = CGRect(
            x: box.minX.rounded(), y: box.minY.rounded(),
            width: box.width.rounded(), height: box.height.rounded()
        ).intersection(bounds)
        guard !whole.isNull, whole.width >= minimumSide, whole.height >= minimumSide else { return nil }
        return whole
    }

    /// The crop moved to the origin, so both sides of a registration share one extent. Core
    /// Image's origin is at the bottom left.
    private static func crop(_ buffer: CVPixelBuffer, to rect: CGRect) -> CIImage {
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        let cropRect = CGRect(
            x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        return CIImage(cvPixelBuffer: buffer).cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
    }

    private func register(target: CIImage, on current: CIImage) -> CGPoint? {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: target, options: [:])
        guard (try? VNImageRequestHandler(ciImage: current, options: [:]).perform([request])) != nil,
            let observation = request.results?.first
        else { return nil }
        let transform = observation.alignmentTransform
        return CGPoint(x: transform.tx, y: -transform.ty)
    }
}
