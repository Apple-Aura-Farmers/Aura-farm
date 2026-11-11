import CoreGraphics
import Foundation

/// Which parts of the camera frame are the eyepiece ring and which are the open field,
/// learned once by `FieldMaskBuilder`.
struct FieldMask: Equatable {
    var gridWidth: Int
    var gridHeight: Int
    /// Pixels of the frame between neighbouring grid cells.
    var gridStep: Int
    /// Per grid cell, row-major: true = eyepiece (masked).
    var eyepiece: [Bool]
    /// The share of grid cells that are open field.
    var openShare: Double
    /// Where to register, in FULL-FRAME pixels, top-down, whole pixels. nil when the mask is
    /// not trusted.
    var registrationRect: CGRect?

    var isTrusted: Bool { registrationRect != nil }

    /// A small RGBA image of the grid for drawing over the preview: a faint red tint on the
    /// eyepiece cells, clear elsewhere. Made once when the mask is decided, never per frame.
    func tintImage() -> CGImage? {
        guard gridWidth > 0, gridHeight > 0, eyepiece.count == gridWidth * gridHeight else {
            return nil
        }
        // Premultiplied red at about 35% opacity.
        var pixels = [UInt8](repeating: 0, count: gridWidth * gridHeight * 4)
        for (index, masked) in eyepiece.enumerated() where masked {
            pixels[index * 4] = 90
            pixels[index * 4 + 3] = 90
        }
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
