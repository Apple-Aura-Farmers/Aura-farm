import CoreVideo
import Foundation

/// A frame's luma sampled every `step` pixels, copied into a small array so the pixel buffer
/// can be let go straight away.
enum LumaGrid {
    /// Row-major luma and the grid's size, or nil when the buffer has no luma plane.
    static func sample(of buffer: CVPixelBuffer, step: Int) -> (luma: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard step > 0, CVPixelBufferGetPlaneCount(buffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0) / step
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0) / step
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var grid = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = pixels + y * step * bytesPerRow
            for x in 0..<width { grid[y * width + x] = row[x * step] }
        }
        return (grid, width, height)
    }
}
