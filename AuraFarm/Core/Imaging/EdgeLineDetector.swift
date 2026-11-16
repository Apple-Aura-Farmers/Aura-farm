import CoreGraphics
import CoreVideo
import Foundation

/// The numbers `EdgeLineDetector` decides with. Data, not logic. All PLACEHOLDER: the first
/// measurement only logs the result, so they are to be calibrated from the next test's
/// `edge_line_strength`, `edge_line_coverage` and `edge_line_slide_residual` columns.
struct EdgeLineThresholds {
    /// Lines up to this far from perpendicular to the normal are tried, in steps. PLACEHOLDER:
    /// 60 because the 16 Nov 2026 22:56 wavy top edge read -40.5 to -45 (strength 9 to 11,
    /// coverage 1.0) and was dropped at the old 45 (the 15:32 corner band ran at 45 to 50).
    /// 4.5 degree steps make it 27 angles (13 steps a side); a line within one step of the limit
    /// is a side edge the search could not place, not a candidate.
    var maxAngleDegrees = 60.0
    var angleStepDegrees = 4.5
    /// The gradient is taken on the luma minus its box blur of this share of the box's side, so
    /// the eyepiece's illumination falloff (a smooth ramp) is gone. PLACEHOLDER.
    var backgroundBlurShare = 1.0 / 6
    /// The path's bin in a part must also exceed this times the median |mean gradient| of the
    /// bins 3 to 6 away on both sides: a narrow line, not a ramp. PLACEHOLDER.
    var peakOverNeighbours = 2.0
    var neighbourNearBins = 3
    var neighbourFarBins = 6
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
    /// A candidate line: covers most of the picture, or a run of this many contiguous parts (a
    /// corner: the line crosses only part of the box), and stands well out of the noise.
    /// PLACEHOLDER: calibrate from `edge_line_*`.
    var candidateCoverage = 0.75
    var candidateRun = 5
    /// PLACEHOLDER: 8. Real edges read 8.8 to 12.1 in the 16 Nov 2026 22:04 dark lighting and 26
    /// to 53 in the 15:32 bright field; non-edge lines read at most 4.4 (dark) and 7.03 (bright).
    /// Strength alone no longer decides: `LineEdgeThresholds.beyondShareMax` is the second factor.
    var candidateStrength = 8.0
    /// The bands either side of the path where the texture is compared (see `EdgeLine.beforeEnergy`)
    /// run from `beyondGapFields` to `beyondGapFields + bandFields` away from it. PLACEHOLDER.
    var beyondGapFields = 0.06
    var bandFields = 0.30
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
    /// The share of the parts whose gradient is clear of the noise and stands out of its
    /// neighbouring bins, with the path's sign.
    var coverage: Double
    /// The longest run of contiguous covered parts, of `EdgeLineThresholds.segments`.
    var longestRun: Int
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
    /// The mean gradient energy (|gradient|^2 of the picture with its slow illumination taken
    /// away, both axes) in a band behind the line and in one beyond it, on the heading side. Each
    /// band runs from `beyondGapFields` to that plus `bandFields` from the path, parallel to it,
    /// inside the box. A cover-slip edge has the texture before it and little or none beyond it.
    /// nil when not measured.
    var beforeEnergy: Double?
    var beyondEnergy: Double?
    /// Where `slideResidualFields` came from: "tracker" (the live position), "chain" (the sum of
    /// the frame-to-frame shifts, for when the position is frozen), or empty (neither).
    var attachSource = ""
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

        // The picture without its slow illumination: luma minus a box blur, then the gradient
        // along the normal (central differences).
        let side = max(Int(Double(min(width, height)) * thresholds.backgroundBlurShare), 3)
        let margin = side / 2 + 1
        guard width > 2 * margin + 8, height > 2 * margin + 8 else { return nil }
        let flat = removingBackground(grid.luma, width, height, side: side)
        var gradient = [Float](repeating: 0, count: width * height)
        let fx = Float(nx) / 2
        let fy = Float(ny) / 2
        for y in margin..<(height - margin) {
            for x in margin..<(width - margin) {
                let i = y * width + x
                gradient[i] = (flat[i + 1] - flat[i - 1]) * fx + (flat[i + width] - flat[i - width]) * fy
            }
        }

        // The wander lets a line a few degrees off still score alike, so the strength alone does
        // not say the angle: among the angles within 15% of the strongest, the straightest path
        // (the truest angle) wins, the stronger of equals.
        var found: [Candidate] = []
        let steps = Int((thresholds.maxAngleDegrees / thresholds.angleStepDegrees).rounded())
        for k in -steps...steps {
            let degrees = Double(k) * thresholds.angleStepDegrees
            if let candidate = bestPath(
                gradient, width, height, nx, ny, margin: margin, degrees: degrees, thresholds: thresholds)
            {
                found.append(candidate)
            }
        }
        let strongest = found.map(\.strength).max() ?? 0
        let best =
            found.filter { $0.strength >= strongest * 0.85 }
            .min { ($0.roughness, -$0.strength) < ($1.roughness, -$1.strength) }
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
        let energies = bandEnergies(
            flat, width, height, margin: margin, nx: nx, ny: ny, line: line,
            cellsPerField: Double(box.width) / Double(grid.step), thresholds: thresholds)
        let span = Double(min(width, height)) / 2 - Double(margin)
        let points = line.distances.enumerated().map { index, distance in
            let along = -span + (Double(index) + 0.5) * 2 * span / Double(line.distances.count)
            let x = Double(width) / 2 + distance * normalX - along * normalY
            let y = Double(height) / 2 + distance * normalY + along * normalX
            return CGPoint(
                x: Double(box.minX) + x * Double(grid.step),
                y: Double(box.minY) + y * Double(grid.step))
        }
        return EdgeLine(
            strength: line.strength, coverage: line.coverage, longestRun: line.longestRun,
            angleDegrees: line.degrees,
            offsetFields: offsetFields, sign: line.sign, slideResidualFields: residual,
            path: points,
            // A line at (or within one step of) the search limit is a line outside the range
            // that was searched, such as the side edge of a column, not an edge to be found.
            isCandidate: (line.coverage >= thresholds.candidateCoverage
                || line.longestRun >= thresholds.candidateRun)
                && line.strength >= thresholds.candidateStrength
                && abs(line.degrees) < thresholds.maxAngleDegrees - thresholds.angleStepDegrees - 1e-9,
            beforeEnergy: energies.before, beyondEnergy: energies.beyond)
    }

    /// The texture energy in the bands before and beyond the path, per cell.
    private static func bandEnergies(
        _ flat: [Float], _ width: Int, _ height: Int, margin: Int, nx: Double, ny: Double,
        line: Candidate, cellsPerField: Double, thresholds: EdgeLineThresholds
    ) -> (before: Double, beyond: Double) {
        let radians = line.degrees * .pi / 180
        let normalX = nx * cos(radians) - ny * sin(radians)
        let normalY = nx * sin(radians) + ny * cos(radians)
        let parts = line.distances.count
        let halfSpan = Double(min(width, height)) / 2 - Double(margin)
        let partLength = 2 * halfSpan / Double(parts)
        let near = thresholds.beyondGapFields * cellsPerField
        let far = near + thresholds.bandFields * cellsPerField
        var sums = (before: 0.0, beyond: 0.0)
        var counts = (before: 0, beyond: 0)
        let centreX = Double(width) / 2
        let centreY = Double(height) / 2
        for y in (margin + 1)..<(height - margin - 1) {
            let dy = Double(y) + 0.5 - centreY
            for x in (margin + 1)..<(width - margin - 1) {
                let dx = Double(x) + 0.5 - centreX
                let along = -dx * normalY + dy * normalX
                guard abs(along) < halfSpan else { continue }
                let part = min(Int((along + halfSpan) / partLength), parts - 1)
                let delta = dx * normalX + dy * normalY - line.distances[part]
                guard abs(delta) >= near, abs(delta) <= far else { continue }
                let i = y * width + x
                let gx = Double(flat[i + 1] - flat[i - 1]) / 2
                let gy = Double(flat[i + width] - flat[i - width]) / 2
                if delta > 0 {
                    sums.beyond += gx * gx + gy * gy
                    counts.beyond += 1
                } else {
                    sums.before += gx * gx + gy * gy
                    counts.before += 1
                }
            }
        }
        return (
            counts.before > 0 ? sums.before / Double(counts.before) : 0,
            counts.beyond > 0 ? sums.beyond / Double(counts.beyond) : 0
        )
    }

    private struct Candidate {
        var strength: Double
        var coverage: Double
        var longestRun: Int
        /// The sum of the bin changes between neighbouring parts: 0 for a straight path.
        var roughness: Int
        var degrees: Double
        var sign: Int
        /// Per part: the path's distance from the centre along the angle's normal, in cells.
        var distances: [Double]
    }

    /// The picture minus its box blur of `side` cells (a window clipped at the border), by an
    /// integral image.
    private static func removingBackground(
        _ luma: [Float], _ width: Int, _ height: Int, side: Int
    ) -> [Float] {
        var integral = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0.0
            for x in 0..<width {
                row += Double(luma[y * width + x])
                integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + row
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        let half = side / 2
        for y in 0..<height {
            let y0 = max(y - half, 0)
            let y1 = min(y + half + 1, height)
            for x in 0..<width {
                let x0 = max(x - half, 0)
                let x1 = min(x + half + 1, width)
                let total =
                    integral[y1 * (width + 1) + x1] - integral[y0 * (width + 1) + x1]
                    - integral[y1 * (width + 1) + x0] + integral[y0 * (width + 1) + x0]
                out[y * width + x] = luma[y * width + x] - Float(total / Double((x1 - x0) * (y1 - y0)))
            }
        }
        return out
    }

    /// The best one-sign path for one angle: bin the gradient by distance along the angle's
    /// normal and part along the line, then a small dynamic-programming pass over the parts.
    private static func bestPath(
        _ gradient: [Float], _ width: Int, _ height: Int, _ nx: Double, _ ny: Double,
        margin: Int, degrees: Double, thresholds: EdgeLineThresholds
    ) -> Candidate? {
        let radians = degrees * .pi / 180
        let normalX = nx * cos(radians) - ny * sin(radians)
        let normalY = nx * sin(radians) + ny * cos(radians)
        let parts = thresholds.segments
        let halfSpan = Double(min(width, height)) / 2 - Double(margin)
        let reach = halfSpan * 1.5
        let bins = Int((2 * reach / thresholds.binWidth).rounded(.up))
        let partLength = 2 * halfSpan / Double(parts)
        var sums = [Float](repeating: 0, count: bins * parts)
        var counts = [Int32](repeating: 0, count: bins * parts)
        let centreX = Double(width) / 2
        let centreY = Double(height) / 2
        let binScale = 1 / thresholds.binWidth
        let partScale = 1 / partLength
        // The hot loop (angles x cells).
        gradient.withUnsafeBufferPointer { source in
            sums.withUnsafeMutableBufferPointer { sums in
                counts.withUnsafeMutableBufferPointer { counts in
                    for y in margin..<(height - margin) {
                        let dy = Double(y) + 0.5 - centreY
                        for x in margin..<(width - margin) {
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
            // A part counts only when it is clear of the noise AND stands out of the bins a few
            // away on both sides: a narrow line, not a ramp.
            var passes = [Bool](repeating: false, count: parts)
            var sum = 0.0
            for part in 0..<parts {
                let value = signed * means[path[part] * parts + part]
                let neighbours = neighbourMedian(
                    means, counts: counts, bin: path[part], part: part, bins: bins, parts: parts,
                    thresholds: thresholds)
                if value >= thresholds.coverageSigma * noise,
                    value > thresholds.peakOverNeighbours * neighbours
                {
                    passes[part] = true
                    sum += value
                }
            }
            let strength = sum / Double(parts) / noise
            guard strength > (best?.strength ?? -.infinity) else { continue }
            var run = 0
            var longest = 0
            for passed in passes {
                run = passed ? run + 1 : 0
                longest = max(longest, run)
            }
            best = Candidate(
                strength: strength, coverage: Double(passes.filter { $0 }.count) / Double(parts),
                longestRun: longest,
                roughness: zip(path, path.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) },
                degrees: degrees, sign: sign,
                distances: path.map { (Double($0) + 0.5) * thresholds.binWidth - reach })
        }
        return best
    }

    /// The median |mean gradient| of the judged bins 3 to 6 away on both sides, in a part.
    private static func neighbourMedian(
        _ means: [Double], counts: [Int32], bin: Int, part: Int, bins: Int, parts: Int,
        thresholds: EdgeLineThresholds
    ) -> Double {
        var values: [Double] = []
        for distance in thresholds.neighbourNearBins...thresholds.neighbourFarBins {
            for other in [bin - distance, bin + distance]
            where other >= 0 && other < bins && counts[other * parts + part] >= Int32(thresholds.minCells) {
                values.append(abs(means[other * parts + part]))
            }
        }
        return median(values) ?? 0
    }

    private static func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.sorted()[values.count / 2]
    }
}
