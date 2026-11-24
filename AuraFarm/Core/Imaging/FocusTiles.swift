import CoreGraphics
import CoreVideo
import Foundation

/// The numbers `FocusTiles` decides with. Data, not logic. All PLACEHOLDER: measured, logged and
/// labelled first; nothing the app decides reads them yet.
struct FocusTilesThresholds {
    /// The box is split into `grid` x `grid` tiles.
    var grid = 8
    /// Pixels between samples for the fine and the coarse Laplacian.
    var fineStep = 2
    var coarseStep = 6
    /// A tile darker than this mean luma, or with more than `maxSaturatedShare` of its samples at
    /// 255, is left out.
    var minMeanLuma = 20.0
    var maxSaturatedShare = 0.02
    /// Fewer measured tiles than this: no reading.
    var minUsedTiles = 16
    /// The sharpest tiles `top` is the mean of.
    var topTiles = 4
    /// A tile is active when its fine is at least this many times the noise.
    var activeFactor = 3.0
    /// The Laplacian variance over the mean luma squared, times this, so brightness cancels.
    var scale = 10_000.0
}

/// What one frame's focus tiles said.
struct FocusTilesReading: Equatable {
    /// The mean fine of the sharpest tiles.
    var top: Double
    /// For those tiles: mean fine over mean coarse.
    var topRatio: Double
    /// Their indices (row * 8 + column from the top left), ascending.
    var topTiles: [Int]
    /// The mean fine of the lowest quarter of the used tiles.
    var noise: Double
    var used: Int
    /// How many tiles have fine of at least `activeFactor` times the noise.
    var active: Int
    /// All 64 fine values; nil where a tile was left out.
    var tileFine: [Double?]
}

/// Focus measured per tile, so a view with little sample in it still has a number: the sharp tiles
/// say it, the blank ones do not dilute it. Each tile is measured on its own pixels. Pure: luma in,
/// a reading out.
enum FocusTiles {
    /// The reading of `box` (frame pixels from the top left) in `buffer`'s luma plane.
    static func measure(
        of buffer: CVPixelBuffer, in box: CGRect, thresholds: FocusTilesThresholds = FocusTilesThresholds()
    ) -> FocusTilesReading? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let minX = max(Int(box.minX.rounded()), 0)
        let minY = max(Int(box.minY.rounded()), 0)
        let maxX = min(Int(box.maxX.rounded()), width)
        let maxY = min(Int(box.maxY.rounded()), height)
        guard maxX > minX, maxY > minY else { return nil }
        return measure(
            pixels: base.assumingMemoryBound(to: UInt8.self), bytesPerRow: bytesPerRow,
            region: (minX, minY, maxX, maxY), thresholds: thresholds)
    }

    private static func measure(
        pixels: UnsafePointer<UInt8>, bytesPerRow: Int, region: (Int, Int, Int, Int),
        thresholds t: FocusTilesThresholds
    ) -> FocusTilesReading? {
        let (minX, minY, maxX, maxY) = region
        let grid = t.grid
        let tileWidth = Double(maxX - minX) / Double(grid)
        let tileHeight = Double(maxY - minY) / Double(grid)
        var fine = [Double?](repeating: nil, count: grid * grid)
        var coarse = [Double](repeating: 0, count: grid * grid)
        for row in 0..<grid {
            for column in 0..<grid {
                let x0 = minX + Int((Double(column) * tileWidth).rounded())
                let x1 = minX + Int((Double(column + 1) * tileWidth).rounded())
                let y0 = minY + Int((Double(row) * tileHeight).rounded())
                let y1 = minY + Int((Double(row + 1) * tileHeight).rounded())
                guard
                    let f = tile(
                        pixels, bytesPerRow, x0, y0, x1, y1, step: t.fineStep, measuresLuma: true),
                    f.mean >= t.minMeanLuma, f.saturatedShare <= t.maxSaturatedShare,
                    let c = tile(
                        pixels, bytesPerRow, x0, y0, x1, y1, step: t.coarseStep,
                        measuresLuma: false)
                else { continue }
                let norm = t.scale / (f.mean * f.mean)
                fine[row * grid + column] = f.variance * norm
                coarse[row * grid + column] = c.variance * norm
            }
        }
        let usedIndices = fine.indices.filter { fine[$0] != nil }
        guard usedIndices.count >= t.minUsedTiles else { return nil }
        let byFine = usedIndices.sorted {
            let a = fine[$0] ?? 0
            let b = fine[$1] ?? 0
            return a != b ? a > b : $0 < $1
        }
        let top = Array(byFine.prefix(t.topTiles))
        let topFine = top.map { fine[$0] ?? 0 }.reduce(0, +) / Double(top.count)
        let topCoarse = top.map { coarse[$0] }.reduce(0, +) / Double(top.count)
        let lowest = byFine.suffix(max(usedIndices.count / 4, 1))
        let noise = lowest.map { fine[$0] ?? 0 }.reduce(0, +) / Double(lowest.count)
        let active = usedIndices.filter {
            let value = fine[$0] ?? 0
            return value > 0 && value >= t.activeFactor * noise
        }.count
        return FocusTilesReading(
            top: topFine, topRatio: topCoarse > 1e-9 ? topFine / topCoarse : 0,
            topTiles: top.sorted(), noise: noise, used: usedIndices.count, active: active,
            tileFine: fine)
    }

    /// The variance of the 4-neighbour Laplacian over the samples `step` pixels apart inside a
    /// tile (no pixel from another tile is read), with the tile's mean luma and share of samples
    /// at 255 (only worked out for the fine pass).
    private static func tile(
        _ pixels: UnsafePointer<UInt8>, _ bytesPerRow: Int, _ x0: Int, _ y0: Int, _ x1: Int,
        _ y1: Int, step: Int, measuresLuma: Bool
    ) -> (variance: Double, mean: Double, saturatedShare: Double)? {
        let w = (x1 - x0) / step
        let h = (y1 - y0) / step
        guard w > 2, h > 2 else { return nil }
        let stride = step * bytesPerRow
        var lapSum = 0.0
        var lapSquares = 0.0
        var lumaSum = 0.0
        var saturated = 0
        var count = 0.0
        for y in 1..<(h - 1) {
            var p = pixels + (y0 + y * step) * bytesPerRow + x0 + step
            for _ in 1..<(w - 1) {
                let centre = Int(p.pointee)
                let lap = Double(
                    4 * centre - Int(p[-step]) - Int(p[step]) - Int(p[-stride]) - Int(p[stride]))
                lapSum += lap
                lapSquares += lap * lap
                if measuresLuma {
                    lumaSum += Double(centre)
                    if centre == 255 { saturated += 1 }
                }
                count += 1
                p += step
            }
        }
        guard count > 0 else { return nil }
        let mean = lapSum / count
        return (
            max(lapSquares / count - mean * mean, 0), lumaSum / count,
            Double(saturated) / count
        )
    }
}
