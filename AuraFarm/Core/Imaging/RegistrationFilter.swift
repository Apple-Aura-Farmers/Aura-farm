import Accelerate
import CoreGraphics
import CoreVideo
import Foundation

/// The numbers `RegistrationFilter` uses. Data, not logic. All PLACEHOLDER. Source: the 16 Nov
/// 2026 14:20 run (soil, phone and slide still). A strong static brightness gradient in the view
/// (a vignette band and a shadow patch) dominated the registration and made one frame in about
/// 1.5 s read +-242 px in x. Offline, with these numbers all 30 still pairs read within 2 px and
/// every synthetic shift (+-10 to 60 px) within 2 px with no cross-axis error.
struct RegistrationFilterThresholds {
    /// The sigma of the blur that is taken away, in px of the box crop.
    var blurSigmaPx = 12.0
    /// How much the remaining detail is multiplied by before it is centred on `mid`.
    var gain = 4.0
    /// The output level of "no detail", 0...1.
    var mid = 0.5
}

/// A high-pass for registration: `clamp((luma - blur(luma)) x gain + mid, 0, 1)`, so the slow
/// brightness gradient is gone and only the texture is left for Vision to line up.
///
/// The blur is a true Gaussian: a separable float kernel (`vImageSepConvolve_PlanarF`, edges
/// extended) of radius 3 sigma. vImage has no float box or tent convolution to approximate it
/// with. The arithmetic is done in floats, so nothing is clamped before the last step.
enum RegistrationFilter {
    /// The luma of `rect` (whole pixels, top-left origin) of a camera buffer; nil when the buffer
    /// has no luma plane or the rect leaves it.
    static func luma(
        of buffer: CVPixelBuffer, in rect: CGRect
    ) -> (bytes: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return nil }
        let x = Int(rect.minX)
        let y = Int(rect.minY)
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard x >= 0, y >= 0, width > 0, height > 0,
            x + width <= CVPixelBufferGetWidthOfPlane(buffer, 0),
            y + height <= CVPixelBufferGetHeightOfPlane(buffer, 0)
        else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let plane = base.assumingMemoryBound(to: UInt8.self)
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { target in
            guard let start = target.baseAddress else { return }
            for row in 0..<height {
                memcpy(start + row * width, plane + (y + row) * rowBytes + x, width)
            }
        }
        return (bytes, width, height)
    }

    /// The luma of a stored picture (drawn into an 8-bit gray context).
    static func luma(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (bytes, width, height) : nil
    }

    /// The filtered picture as an 8-bit gray image; nil when the size is too small to blur.
    static func highPass(
        _ luma: (bytes: [UInt8], width: Int, height: Int),
        thresholds: RegistrationFilterThresholds = RegistrationFilterThresholds()
    ) -> CGImage? {
        let width = luma.width
        let height = luma.height
        let count = width * height
        let radius = min(Int((3 * thresholds.blurSigmaPx).rounded(.up)), (min(width, height) - 1) / 2)
        guard radius >= 1, count > 0 else { return nil }
        let sigma = Float(thresholds.blurSigmaPx)
        var kernel = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
        let total = kernel.reduce(0, +)
        kernel = kernel.map { $0 / total }

        var source = [Float](repeating: 0, count: count)
        vDSP.convertElements(of: luma.bytes, to: &source)
        var blurred = [Float](repeating: 0, count: count)
        let done = source.withUnsafeMutableBytes { from in
            blurred.withUnsafeMutableBytes { to -> Bool in
                var input = vImage_Buffer(
                    data: from.baseAddress, height: vImagePixelCount(height),
                    width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.size)
                var output = vImage_Buffer(
                    data: to.baseAddress, height: vImagePixelCount(height),
                    width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.size)
                let error = vImageSepConvolve_PlanarF(
                    &input, &output, nil, 0, 0, kernel, UInt32(kernel.count), kernel,
                    UInt32(kernel.count), 0, 0, vImage_Flags(kvImageEdgeExtend))
                return error == kvImageNoError
            }
        }
        guard done else { return nil }

        // (luma - blur) / 255 x gain + mid, clamped to 0...1, then to 0...255.
        var out = vDSP.subtract(source, blurred)
        out = vDSP.add(
            Float(thresholds.mid * 255), vDSP.multiply(Float(thresholds.gain), out))
        out = vDSP.clip(out, to: 0...255)
        let bytes = vDSP.floatingPointToInteger(out, integerType: UInt8.self, rounding: .towardNearestInteger)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
