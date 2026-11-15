import CoreGraphics
import Foundation

/// Measures one luma grid for `AlignmentCheck`: where the microscope's bright circle is, and
/// whether it is whole, round, even and free of glare. Pure.
enum AlignmentMeasure {
    static func measure(
        luma: [UInt8], gridWidth: Int, gridHeight: Int, gridStep: Int,
        thresholds: AlignmentThresholds, contrastRatio: Double = FieldMaskThresholds().minContrastRatio
    ) -> AlignmentReading {
        var reading = AlignmentReading()
        let count = gridWidth * gridHeight
        guard gridWidth > 1, gridHeight > 1, luma.count >= count else {
            reading.problems = [.noCircle]
            return reading
        }
        // The same automatic cut the eyepiece mask learner uses, at its plain value.
        let cut = FieldMaskBuilder.darkCut(of: luma, count: count, minRatio: contrastRatio, scale: 1)
        guard cut > 0 else {
            reading.problems = [.noCircle]
            return reading
        }
        let region = largestBrightRegion(
            luma: luma, cut: cut, width: gridWidth, height: gridHeight)
        let share = Double(region.count) / Double(count)
        guard share >= thresholds.minCircleShareOfFrame else {
            reading.problems = [.noCircle]
            return reading
        }
        reading.found = true

        // The centroid and the radius from the area, in grid cells.
        var sumX = 0.0
        var sumY = 0.0
        for index in region {
            sumX += Double(index % gridWidth)
            sumY += Double(index / gridWidth)
        }
        let area = Double(region.count)
        let cx = sumX / area
        let cy = sumY / area
        let radius = (area / .pi).squareRoot()
        let step = Double(gridStep)
        reading.circle = FieldCircle(
            centre: CGPoint(x: (cx + 0.5) * step, y: (cy + 0.5) * step), radius: radius * step)

        // Border contact, per side, as a share of all the border's cells.
        let perimeter = Double(2 * (gridWidth + gridHeight) - 4)
        var touching: [FrameSide: Int] = [:]
        for index in region {
            let x = index % gridWidth
            let y = index / gridWidth
            if y == 0 { touching[.top, default: 0] += 1 }
            if y == gridHeight - 1 { touching[.bottom, default: 0] += 1 }
            if x == 0 { touching[.left, default: 0] += 1 }
            if x == gridWidth - 1 { touching[.right, default: 0] += 1 }
        }
        for (side, cells) in touching where Double(cells) / perimeter > thresholds.maxBorderTouchShare {
            reading.clippedSides.insert(side)
        }
        let touchShare = touching.values.max().map { Double($0) / perimeter } ?? 0

        // Roundness: the bright area over the area of the circle that encloses it.
        var farthest = 0.0
        for index in region {
            let dx = Double(index % gridWidth) - cx
            let dy = Double(index / gridWidth) - cy
            farthest = max(farthest, (dx * dx + dy * dy).squareRoot())
        }
        let roundness = farthest > 0 ? min(area / (.pi * farthest * farthest), 1) : 0
        reading.roundness = roundness

        // Sectors, saturation and glare, from the cells inside the circle.
        let sectors = max(thresholds.sectorCount, 1)
        var sums = [Double](repeating: 0, count: sectors)
        var counts = [Int](repeating: 0, count: sectors)
        var inside = 0
        var saturated = 0
        let limit = radius * radius
        let inner = limit * thresholds.sectorRadiusShare * thresholds.sectorRadiusShare
        let sliver = 2 * Double.pi / Double(sectors)
        for y in 0..<gridHeight {
            for x in 0..<gridWidth {
                let dx = Double(x) - cx
                let dy = Double(y) - cy
                let squared = dx * dx + dy * dy
                guard squared <= limit else { continue }
                let value = Int(luma[y * gridWidth + x])
                inside += 1
                if value >= thresholds.saturatedLuma { saturated += 1 }
                guard squared <= inner else { continue }
                var angle = atan2(dy, dx) + sliver / 2
                if angle < 0 { angle += 2 * .pi }
                let sector = min(Int(angle / sliver), sectors - 1) % sectors
                sums[sector] += Double(value)
                counts[sector] += 1
            }
        }
        let means = (0..<sectors).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : 0 }
        reading.sectorMeans = means
        let brightest = means.enumerated().max { $0.element < $1.element }
        let darkest = means.enumerated().min { $0.element < $1.element }
        reading.brightestSector = brightest?.offset
        reading.darkestSector = darkest?.offset
        let evenness = (brightest?.element ?? 0) > 0 ? (darkest?.element ?? 0) / (brightest?.element ?? 1) : 0
        reading.evenness = evenness
        let sorted = means.sorted()
        let median =
            sorted.count % 2 == 0
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        let glare = median > 0 ? (brightest?.element ?? 0) / median : 1
        reading.glareRatio = glare
        let saturatedShare = inside > 0 ? Double(saturated) / Double(inside) : 0
        reading.saturatedShare = saturatedShare

        if !reading.clippedSides.isEmpty { reading.problems.append(.clipped) }
        if roundness < thresholds.minRoundness { reading.problems.append(.notRound) }
        if evenness < thresholds.minEvenness { reading.problems.append(.uneven) }
        if saturatedShare > thresholds.maxSaturatedShare || glare > thresholds.maxGlareRatio {
            reading.problems.append(.glare)
        }

        func margin(_ value: Double) -> Double { min(max(value, 0), 1) }
        let margins = [
            margin((share - thresholds.minCircleShareOfFrame) / thresholds.minCircleShareOfFrame),
            margin(1 - touchShare / max(thresholds.maxBorderTouchShare, 1e-9)),
            margin((roundness - thresholds.minRoundness) / max(1 - thresholds.minRoundness, 1e-9)),
            margin((evenness - thresholds.minEvenness) / max(1 - thresholds.minEvenness, 1e-9)),
            margin(1 - saturatedShare / max(thresholds.maxSaturatedShare, 1e-9)),
            margin((thresholds.maxGlareRatio - glare) / max(thresholds.maxGlareRatio - 1, 1e-9)),
        ]
        let mean = margins.reduce(0, +) / Double(margins.count)
        reading.score = 100 * (0.5 * (margins.min() ?? 0) + 0.5 * mean)
        return reading
    }

    /// The cells (as row-major indices) of the largest 4-connected region at or above `cut`.
    private static func largestBrightRegion(
        luma: [UInt8], cut: Double, width: Int, height: Int
    ) -> [Int] {
        var visited = [Bool](repeating: false, count: width * height)
        var best: [Int] = []
        var stack: [Int] = []
        for start in 0..<(width * height) where !visited[start] && Double(luma[start]) >= cut {
            var cells: [Int] = []
            visited[start] = true
            stack.append(start)
            while let index = stack.popLast() {
                cells.append(index)
                let x = index % width
                let y = index / width
                if x > 0 { push(index - 1) }
                if x < width - 1 { push(index + 1) }
                if y > 0 { push(index - width) }
                if y < height - 1 { push(index + width) }
            }
            if cells.count > best.count { best = cells }

            func push(_ neighbour: Int) {
                if !visited[neighbour], Double(luma[neighbour]) >= cut {
                    visited[neighbour] = true
                    stack.append(neighbour)
                }
            }
        }
        return best
    }
}
