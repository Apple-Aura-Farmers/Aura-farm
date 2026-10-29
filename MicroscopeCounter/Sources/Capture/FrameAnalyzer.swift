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
final class ShakeEstimator {
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
        guard let previous else { return nil }

        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: previous)
        do {
            try handler.perform([request], on: buffer)
        } catch {
            return nil
        }
        guard let observation = (request.results as? [VNImageTranslationAlignmentObservation])?.first else {
            return nil
        }

        let shift = hypot(observation.alignmentTransform.tx, observation.alignmentTransform.ty)
        recent.append(Double(shift))
        if recent.count > windowSize { recent.removeFirst() }
        return recent.reduce(0, +) / Double(recent.count)
    }

    func reset() {
        previous = nil
        recent = []
    }
}
