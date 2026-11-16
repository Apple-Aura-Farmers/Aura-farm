import CoreGraphics
import CoreVideo
import Foundation

/// How much of the box holds distinct small features, whatever the variance averages to: the
/// box is cut into a 6 x 6 grid and a cell with at least `minFeaturePixels` strong
/// Laplacian pixels is a feature cell.
struct FeatureCells: Equatable {
    /// Feature cells, 0 to 36.
    var cells = 0
    /// How many of the box's 4 quarters hold at least one feature cell.
    var quarters = 0
}

extension FrameAnalyzer {
    /// Cells per side of the box's grid.
    static let featureGrid = 6
    /// A cell needs at least this many feature pixels. PLACEHOLDER: one stray pixel is noise.
    static let minFeaturePixels = 2

    /// The feature cells of `box` (frame pixels), at step 2: a pixel is a feature when its
    /// 4-neighbour Laplacian is at least `featureContrast` in magnitude (luma units). nil when
    /// the box cannot be measured.
    static func featureCells(
        of pixelBuffer: CVPixelBuffer, in box: CGRect, featureContrast: Double
    ) -> FeatureCells? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else { return nil }
        let step = 2
        let minX = max(Int(box.minX.rounded()), 0)
        let minY = max(Int(box.minY.rounded()), 0)
        let maxX = min(Int(box.maxX.rounded()), CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        let maxY = min(Int(box.maxY.rounded()), CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
        let width = (maxX - minX) / step
        let height = (maxY - minY) / step
        guard width > 2 * featureGrid, height > 2 * featureGrid else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let grid = featureGrid
        var counts = [Int](repeating: 0, count: grid * grid)
        let limit = Int(featureContrast.rounded(.up))
        for y in 1..<(height - 1) {
            let row = pixels + (minY + y * step) * bytesPerRow + minX
            let above = row - step * bytesPerRow
            let below = row + step * bytesPerRow
            let cellRow = min(y * grid / height, grid - 1)
            for x in 1..<(width - 1) {
                let centre = Int(row[x * step])
                let laplacian =
                    4 * centre - Int(row[(x - 1) * step]) - Int(row[(x + 1) * step])
                    - Int(above[x * step]) - Int(below[x * step])
                if abs(laplacian) >= limit {
                    counts[cellRow * grid + min(x * grid / width, grid - 1)] += 1
                }
            }
        }
        var result = FeatureCells()
        var quarters = Set<Int>()
        for row in 0..<grid {
            for column in 0..<grid where counts[row * grid + column] >= minFeaturePixels {
                result.cells += 1
                quarters.insert((row * 2 / grid) * 2 + column * 2 / grid)
            }
        }
        result.quarters = quarters.count
        return result
    }
}
