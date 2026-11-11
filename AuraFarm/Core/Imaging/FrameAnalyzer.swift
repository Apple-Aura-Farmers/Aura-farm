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
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let w = width / step
        let h = height / step
        guard w > 2, h > 2 else { return nil }

        // Downsampled copy of the luma plane.
        var grid = [Float](repeating: 0, count: w * h)
        var sum = 0.0
        var squares = 0.0
        for y in 0..<h {
            let row = pixels + (y * step) * bytesPerRow
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
