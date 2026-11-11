import CoreGraphics
import Foundation

/// The eyepiece field as a circle, in frame pixels (top-down). Used to adjust a learned mask by
/// hand: the learned mask is turned into a circle, the person moves and resizes it, and the
/// circle is turned back into a `FieldMask`.
struct FieldCircle: Equatable {
    var centre: CGPoint
    var radius: Double

    /// Smallest and largest radius, as shares of the frame's short side.
    /// PLACEHOLDER: not calibrated.
    static let radiusShareRange = 0.1...0.8

    init(centre: CGPoint, radius: Double) {
        self.centre = centre
        self.radius = radius
    }

    /// A circle with the same centre and area as the mask's open cells. nil when none are open.
    init?(fitting mask: FieldMask) {
        guard mask.eyepiece.count == mask.gridWidth * mask.gridHeight else { return nil }
        var count = 0.0
        var sumX = 0.0
        var sumY = 0.0
        for (index, masked) in mask.eyepiece.enumerated() where !masked {
            count += 1
            sumX += Double(index % mask.gridWidth) + 0.5
            sumY += Double(index / mask.gridWidth) + 0.5
        }
        guard count > 0 else { return nil }
        let step = Double(mask.gridStep)
        centre = CGPoint(x: sumX / count * step, y: sumY / count * step)
        radius = (count * step * step / .pi).squareRoot()
    }

    /// The same circle with its radius within `radiusShareRange` of the short side and its
    /// centre inside the frame.
    func clamped(to frameSize: CGSize) -> FieldCircle {
        let shortSide = Double(min(frameSize.width, frameSize.height))
        return FieldCircle(
            centre: CGPoint(
                x: min(max(centre.x, 0), frameSize.width), y: min(max(centre.y, 0), frameSize.height)),
            radius: min(
                max(radius, shortSide * Self.radiusShareRange.lowerBound),
                shortSide * Self.radiusShareRange.upperBound))
    }

    /// The mask this circle describes: everything outside it is eyepiece, and registration
    /// looks in the square inside it (less the inset), cut to the frame, whole pixels.
    func mask(frameSize: CGSize, thresholds: FieldMaskThresholds = .init()) -> FieldMask {
        let step = max(thresholds.gridStep, 1)
        let gridWidth = Int(frameSize.width) / step
        let gridHeight = Int(frameSize.height) / step
        var eyepiece = [Bool](repeating: true, count: gridWidth * gridHeight)
        var open = 0
        for y in 0..<gridHeight {
            for x in 0..<gridWidth {
                let cellX = (Double(x) + 0.5) * Double(step)
                let cellY = (Double(y) + 0.5) * Double(step)
                if hypot(cellX - centre.x, cellY - centre.y) <= radius {
                    eyepiece[y * gridWidth + x] = false
                    open += 1
                }
            }
        }
        let half = radius / 2.0.squareRoot() * (1 - thresholds.insetShare)
        let left = max((centre.x - half).rounded(.up), 0)
        let top = max((centre.y - half).rounded(.up), 0)
        let right = min((centre.x + half).rounded(.down), frameSize.width)
        let bottom = min((centre.y + half).rounded(.down), frameSize.height)
        let rect =
            right > left && bottom > top
            ? CGRect(x: left, y: top, width: right - left, height: bottom - top) : nil
        return FieldMask(
            gridWidth: gridWidth, gridHeight: gridHeight, gridStep: step, eyepiece: eyepiece,
            openShare: eyepiece.isEmpty ? 0 : Double(open) / Double(eyepiece.count),
            registrationRect: rect)
    }
}
