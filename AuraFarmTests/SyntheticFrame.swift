import CoreVideo
import Foundation

/// Builds small 420YpCbCr8BiPlanarFullRange pixel buffers from a luma function, for tests.
enum SyntheticFrame {
    static func make(width: Int, height: Int, luma: (Int, Int) -> UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        guard let buffer else { fatalError("could not create a pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let plane = y.assumingMemoryBound(to: UInt8.self)
            for row in 0..<height {
                for column in 0..<width { plane[row * rowBytes + column] = luma(column, row) }
            }
        }
        if let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let plane = uv.assumingMemoryBound(to: UInt8.self)
            for row in 0..<CVPixelBufferGetHeightOfPlane(buffer, 1) {
                for column in 0..<rowBytes { plane[row * rowBytes + column] = 128 }
            }
        }
        return buffer
    }

    /// Seeded noise, the same every run.
    static func noise(width: Int, height: Int, seed: UInt64 = 42) -> [UInt8] {
        var state = seed
        return (0..<(width * height)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        }
    }

    /// Seeded noise blurred a little, so registration has structure to lock onto.
    static func smoothNoise(size: Int) -> [Double] {
        let raw = noise(width: size, height: size).map(Double.init)
        var out = raw
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                var total = 0.0
                for dy in -1...1 { for dx in -1...1 { total += raw[(y + dy) * size + x + dx] } }
                out[y * size + x] = total / 9
            }
        }
        return out
    }
}
