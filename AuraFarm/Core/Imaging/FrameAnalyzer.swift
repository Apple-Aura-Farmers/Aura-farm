import CoreVideo
import Foundation
import Vision

/// Measures brightness and sharpness from the luma (Y) plane of a camera frame.
/// Expects a bi-planar YUV pixel buffer (420YpCbCr8BiPlanar).
enum FrameAnalyzer {
    /// - Parameter step: sample every Nth pixel in each direction to keep this cheap.
    ///   Sharpness is therefore measured at a coarser scale than the full frame.
    static func brightnessAndSharpness(
        of pixelBuffer: CVPixelBuffer,
        step: Int = 2
    ) -> (brightness: Double, sharpness: Double)? {
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
        for y in 0..<h {
            let row = pixels + (y * step) * bytesPerRow
            for x in 0..<w {
                let value = Float(row[x * step])
                grid[y * w + x] = value
                sum += Double(value)
            }
        }
        let brightness = sum / Double(w * h)

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

        return (brightness, sharpness)
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

    /// The distance from the held frame, or nil when no frame is held yet or the two no
    /// longer have enough in common to be lined up at all.
    func distance(to buffer: CVPixelBuffer) -> Double? {
        guard let held else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: held)
        guard (try? VNSequenceRequestHandler().perform([request], on: buffer)) != nil,
            let observation = request.results?.first
        else { return nil }
        let transform = observation.alignmentTransform
        return Double(hypot(transform.tx, transform.ty))
    }

    /// Call with every frame the sweep keeps: travel is measured from the last of them.
    func hold(_ buffer: CVPixelBuffer) {
        held = buffer
    }

    func reset() {
        held = nil
    }
}
