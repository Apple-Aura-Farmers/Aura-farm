import CoreGraphics
import Foundation

/// The numbers the fallback region uses. Data, not logic.
struct EyepieceFieldThresholds {
    /// When no field mask is trusted, use a square of this centred share of the short side
    /// instead. PLACEHOLDER: not calibrated.
    var fallbackShare: Double = 0.7
}

/// Regions to register in. The eyepiece itself is found by `FieldMaskBuilder`.
enum EyepieceField {
    /// A centred square of `fallbackShare` of the short side, in whole pixels, top-down.
    static func centreSquare(
        frameSize: CGSize, thresholds: EyepieceFieldThresholds = .init()
    ) -> CGRect {
        let shortSide = Double(min(frameSize.width, frameSize.height))
        // Whole pixels: a region with a fractional origin made Vision's registration read 0.
        let side = (thresholds.fallbackShare * shortSide + 1e-6).rounded(.down)
        let x = ((Double(frameSize.width) - side) / 2).rounded()
        let y = ((Double(frameSize.height) - side) / 2).rounded()
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The same rectangle as a Vision `regionOfInterest`: normalised, with the origin at the
    /// BOTTOM LEFT.
    static func visionRegion(of square: CGRect, frameSize: CGSize) -> CGRect {
        CGRect(
            x: square.minX / frameSize.width,
            y: (frameSize.height - square.maxY) / frameSize.height,
            width: square.width / frameSize.width,
            height: square.height / frameSize.height)
    }
}
