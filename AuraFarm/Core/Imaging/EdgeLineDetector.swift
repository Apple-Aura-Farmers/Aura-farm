import CoreGraphics
import CoreVideo
import Foundation

/// The numbers `EdgeLineDetector` decides with. Data, not logic. All PLACEHOLDER: the first
/// measurement only logs the result, so they are to be calibrated from the next test's
/// `edge_line_strength`, `edge_line_coverage` and `edge_line_slide_residual` columns.
struct EdgeLineThresholds {
    /// Lines up to this far from perpendicular to the normal are tried, in steps.
    var maxAngleDegrees = 12.0
    var angleStepDegrees = 2.0
    /// Analysis pixels (grid cells) per bin across the line.
    var binWidth = 2.0
    /// The line is cut into this many parts along its length.
    var segments = 8
    /// A line may shift by this many bins from one part to the next (irregular edges).
    var maxWanderBins = 2
    /// A part counts as covered when its mean gradient is this many noise units, one sign.
    var coverageSigma = 3.0
    /// The least noise (gradient levels per cell): stops a flat synthetic picture dividing by 0.
    var noiseFloor = 0.5
    /// A (bin, part) with fewer cells than this is not judged.
    var minCells = 6
    /// A candidate line: covers most of the picture and stands well out of the noise.
    var candidateCoverage = 0.75
    var candidateStrength = 6.0
}

/// The box's luma sampled every `step` pixels, row-major, with where it came from.
struct EdgeLineGrid {
    var luma: [Float]
    var width: Int
    var height: Int
    /// Frame pixels per cell.
    var step: Int

    /// Samples `box` (frame pixels, top-left origin) of the buffer's luma plane. nil when the
    /// buffer has no luma or the box is too small.
    static func sample(of buffer: CVPixelBuffer, in box: CGRect, step: Int) -> EdgeLineGrid? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard step > 0, CVPixelBufferGetPlaneCount(buffer) > 0,
            let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return nil }
        let minX = max(Int(box.minX.rounded()), 0)
        let minY = max(Int(box.minY.rounded()), 0)
        let maxX = min(Int(box.maxX.rounded()), CVPixelBufferGetWidthOfPlane(buffer, 0))
        let maxY = min(Int(box.maxY.rounded()), CVPixelBufferGetHeightOfPlane(buffer, 0))
        let width = (maxX - minX) / step
        let height = (maxY - minY) / step
        guard width > 4, height > 4 else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var luma = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = pixels + (minY + y * step) * bytesPerRow + minX
            for x in 0..<width { luma[y * width + x] = Float(row[x * step]) }
        }
        return EdgeLineGrid(luma: luma, width: width, height: height, step: step)
    }
}

/// A line that runs across the whole box, straight or irregular: a cover-slip or mounting-medium
/// edge. LOGGED AND DRAWN ONLY: no guide decision uses it.
struct EdgeLine: Equatable {
    /// The mean gradient along the path over the noise.
    var strength: Double
    /// The share of the parts whose gradient is clear of the noise, with the path's sign.
    var coverage: Double
    /// From the expected line direction (perpendicular to the normal), in degrees.
    var angleDegrees: Double
    /// The path's mean distance from the box centre along the normal, in fields; positive is
    /// ahead (along the normal).
    var offsetFields: Double
    /// +1 when it is brighter ahead, -1 when darker.
    var sign: Int
    /// With a previous result and the tracked movement: how far (fields) the line's change of
    /// offset is from the tracker's change. About 0 means attached to the slide; about the
    /// movement means fixed to the optics (dust). nil without both.
    var slideResidualFields: Double?
    /// The path's points in frame pixels, one per part along the line, for drawing.
    var path: [CGPoint]
    var isCandidate: Bool
}

/// Finds a line across the box where the brightness steps along the expected normal. Soil
/// particles never line up across the whole width, so this can find an edge even when the
/// density on both sides is alike. Pure. Cost: about `angles x cells` additions.
enum EdgeLineDetector {
    /// - Parameters:
    ///   - box: the grid's box in frame pixels; its width is the field (`boxSide`).
    ///   - normal: the expected edge normal in frame pixels (the heading's frame vector).
    ///   - previous: the last result, for `slideResidualFields`.
    ///   - trackedChangeFields: how far the tracker's position moved along the normal since
    ///     `previous`, in fields. The tracker's position is the content's displacement, so a line
    ///     attached to the slide changes its offset by the same amount.
    static func detect(
        grid: EdgeLineGrid, box: CGRect, normal: CGPoint, previous: EdgeLine? = nil,
        trackedChangeFields: Double? = nil, thresholds: EdgeLineThresholds = EdgeLineThresholds()
    ) -> EdgeLine? {
        let length = hypot(Double(normal.x), Double(normal.y))
        let width = grid.width
        let height = grid.height
        guard length > 1e-9, box.width > 0, width > 4, height > 4,
            grid.luma.count == width * height
        else { return nil }
        let nx = Double(normal.x) / length
        let ny = Double(normal.y) / length

        // Gradient along the normal, central differences.
        var gradient = [Float](repeating: 0, count: width * height)
        let fx = Float(nx) / 2
        let fy = Float(ny) / 2
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                gradient[i] =
                    (grid.luma[i + 1] - grid.luma[i - 1]) * fx
                    + (grid.luma[i + width] - grid.luma[i - width]) * fy
            }
        }

        var best: Candidate?
        let steps = Int((thresholds.maxAngleDegrees / thresholds.angleStepDegrees).rounded())
        for k in -steps...steps {
            let degrees = Double(k) * thresholds.angleStepDegrees
            if let found = bestPath(
                gradient, width, height, nx, ny, degrees: degrees, thresholds: thresholds),
                found.strength > (best?.strength ?? -.infinity)
            {
                best = found
            }
        }
        guard let line = best else { return nil }

        let offsetCells = line.distances.reduce(0, +) / Double(line.distances.count)
        let offsetFields = offsetCells * Double(grid.step) / Double(box.width)
        var residual: Double?
        if let previous, let trackedChangeFields {
            residual = abs((offsetFields - previous.offsetFields) - trackedChangeFields)
        }
        let radians = line.degrees * .pi / 180
        let normalX = nx * cos(radians) - ny * sin(radians)
        let normalY = nx * sin(radians) + ny * cos(radians)
        let span = Double(min(width, height)) / 2
        let points = line.distances.enumerated().map { index, distance in
            let along = -span + (Double(index) + 0.5) * 2 * span / Double(line.distances.count)
            let x = Double(width) / 2 + distance * normalX - along * normalY
            let y = Double(height) / 2 + distance * normalY + along * normalX
            return CGPoint(
                x: Double(box.minX) + x * Double(grid.step),
                y: Double(box.minY) + y * Double(grid.step))
        }
        return EdgeLine(
            strength: line.strength, coverage: line.coverage, angleDegrees: line.degrees,
            offsetFields: offsetFields, sign: line.sign, slideResidualFields: residual,
            path: points,
            isCandidate: line.coverage >= thresholds.candidateCoverage
                && line.strength >= thresholds.candidateStrength)
    }

    private struct Candidate {
        var strength: Double
        var coverage: Double
        var degrees: Double
        var sign: Int
        /// Per part: the path's distance from the centre along the angle's normal, in cells.
        var distances: [Double]
    }

    /// The best one-sign path for one angle: bin the gradient by distance along the angle's
    /// normal and part along the line, then a small dynamic-programming pass over the parts.
    private static func bestPath(
        _ gradient: [Float], _ width: Int, _ height: Int, _ nx: Double, _ ny: Double,
        degrees: Double, thresholds: EdgeLineThresholds
    ) -> Candidate? {
        let radians = degrees * .pi / 180
        let normalX = nx * cos(radians) - ny * sin(radians)
        let normalY = nx * sin(radians) + ny * cos(radians)
        let parts = thresholds.segments
        let halfSpan = Double(min(width, height)) / 2
        let reach = halfSpan * 1.5
        let bins = Int((2 * reach / thresholds.binWidth).rounded(.up))
        let partLength = 2 * halfSpan / Double(parts)
        var sums = [Float](repeating: 0, count: bins * parts)
        var counts = [Int32](repeating: 0, count: bins * parts)
        let centreX = Double(width) / 2
        let centreY = Double(height) / 2
        let binScale = 1 / thresholds.binWidth
        let partScale = 1 / partLength
        // The hot loop (angles x cells): unchecked buffers, since every index is clamped above.
        gradient.withUnsafeBufferPointer { source in
            sums.withUnsafeMutableBufferPointer { sums in
                counts.withUnsafeMutableBufferPointer { counts in
                    for y in 1..<(height - 1) {
                        let dy = Double(y) + 0.5 - centreY
                        for x in 1..<(width - 1) {
                            let dx = Double(x) + 0.5 - centreX
                            let along = -dx * normalY + dy * normalX
                            guard abs(along) < halfSpan else { continue }
                            let bin = Int((dx * normalX + dy * normalY + reach) * binScale)
                            guard bin >= 0, bin < bins else { continue }
                            let part = min(Int((along + halfSpan) * partScale), parts - 1)
                            sums[bin * parts + part] += source[y * width + x]
                            counts[bin * parts + part] += 1
                        }
                    }
                }
            }
        }
        var means = [Double](repeating: 0, count: bins * parts)
        var judged: [Double] = []
        for i in 0..<(bins * parts) where counts[i] >= Int32(thresholds.minCells) {
            means[i] = Double(sums[i]) / Double(counts[i])
            judged.append(means[i])
        }
        guard let middle = median(judged) else { return nil }
        let noise = max(
            1.4826 * (median(judged.map { abs($0 - middle) }) ?? 0), thresholds.noiseFloor)

        var best: Candidate?
        for sign in [1, -1] {
            let signed = Double(sign)
            // score[part][bin], and the best total up to each (part, bin) with where it came from.
            var total = [Double](repeating: 0, count: bins * parts)
            var from = [Int](repeating: 0, count: bins * parts)
            for part in 0..<parts {
                for bin in 0..<bins {
                    let score = signed * means[bin * parts + part]
                    if part == 0 {
                        total[bin * parts] = score
                        continue
                    }
                    var top = -Double.infinity
                    var origin = bin
                    let low = max(bin - thresholds.maxWanderBins, 0)
                    let high = min(bin + thresholds.maxWanderBins, bins - 1)
                    for other in low...high where total[other * parts + part - 1] > top {
                        top = total[other * parts + part - 1]
                        origin = other
                    }
                    total[bin * parts + part] = score + top
                    from[bin * parts + part] = origin
                }
            }
            var end = 0
            for bin in 0..<bins where total[bin * parts + parts - 1] > total[end * parts + parts - 1] {
                end = bin
            }
            var path = [Int](repeating: end, count: parts)
            for part in stride(from: parts - 1, to: 0, by: -1) {
                path[part - 1] = from[path[part] * parts + part]
            }
            let sum = total[end * parts + parts - 1]
            let strength = sum / Double(parts) / noise
            let covered = (0..<parts).filter {
                signed * means[path[$0] * parts + $0] >= thresholds.coverageSigma * noise
            }.count
            guard strength > (best?.strength ?? -.infinity) else { continue }
            best = Candidate(
                strength: strength, coverage: Double(covered) / Double(parts), degrees: degrees,
                sign: sign,
                distances: path.map { (Double($0) + 0.5) * thresholds.binWidth - reach })
        }
        return best
    }

    private static func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }
}
