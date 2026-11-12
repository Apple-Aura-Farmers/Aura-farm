import CoreGraphics
import Foundation

/// The picture for "What the app sees": the small luma grid the mask is learned from, with the
/// eyepiece cells tinted red and the registration box outlined in yellow. Drawn at the grid's
/// own size and in the frame's raw orientation, so it shows exactly what the analysis uses,
/// free of any preview rotation or crop.
enum FieldMaskPicture {
    /// RGBA, premultiplied (every pixel opaque), `gridWidth * gridHeight * 4` bytes. Empty
    /// when `luma` is smaller than the grid.
    ///
    /// - Parameters:
    ///   - mask: the learned mask; its cells are tinted when its grid matches this one.
    ///   - registrationRect: the box in FULL-FRAME pixels; drawn as a one cell border.
    ///   - gridStep: frame pixels per grid cell.
    static func rgba(
        luma: [UInt8], gridWidth: Int, gridHeight: Int, mask: FieldMask?,
        registrationRect: CGRect?, gridStep: Int
    ) -> [UInt8] {
        let count = gridWidth * gridHeight
        guard gridWidth > 0, gridHeight > 0, luma.count >= count else { return [] }
        var pixels = [UInt8](repeating: 255, count: count * 4)
        let masked =
            mask.flatMap { $0.gridWidth == gridWidth && $0.gridHeight == gridHeight ? $0 : nil }
        for index in 0..<count {
            let grey = Double(luma[index])
            if let masked, masked.eyepiece[index] {
                // About half red: the grey is halved and red is mixed in.
                pixels[index * 4] = UInt8(min(grey * 0.5 + 127, 255))
                pixels[index * 4 + 1] = UInt8(grey * 0.5)
                pixels[index * 4 + 2] = UInt8(grey * 0.5)
            } else {
                pixels[index * 4] = luma[index]
                pixels[index * 4 + 1] = luma[index]
                pixels[index * 4 + 2] = luma[index]
            }
        }
        if let rect = registrationRect, gridStep > 0 {
            let step = Double(gridStep)
            let left = max(Int((rect.minX / step).rounded(.down)), 0)
            let top = max(Int((rect.minY / step).rounded(.down)), 0)
            let right = min(Int((rect.maxX / step).rounded(.up)) - 1, gridWidth - 1)
            let bottom = min(Int((rect.maxY / step).rounded(.up)) - 1, gridHeight - 1)
            if right >= left, bottom >= top {
                func yellow(_ x: Int, _ y: Int) {
                    let index = (y * gridWidth + x) * 4
                    pixels[index] = 255
                    pixels[index + 1] = 220
                    pixels[index + 2] = 0
                }
                for x in left...right {
                    yellow(x, top)
                    yellow(x, bottom)
                }
                for y in top...bottom {
                    yellow(left, y)
                    yellow(right, y)
                }
            }
        }
        return pixels
    }

    /// The same picture as an image, or nil when it could not be made.
    static func image(
        luma: [UInt8], gridWidth: Int, gridHeight: Int, mask: FieldMask?,
        registrationRect: CGRect?, gridStep: Int
    ) -> CGImage? {
        var pixels = rgba(
            luma: luma, gridWidth: gridWidth, gridHeight: gridHeight, mask: mask,
            registrationRect: registrationRect, gridStep: gridStep)
        guard !pixels.isEmpty else { return nil }
        return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            CGContext(
                data: bytes.baseAddress, width: gridWidth, height: gridHeight,
                bitsPerComponent: 8, bytesPerRow: gridWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }
}
