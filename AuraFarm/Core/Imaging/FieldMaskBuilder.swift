import CoreGraphics
import Foundation

/// Learns the eyepiece mask from several frames.
///
/// The ring is static for the whole session (the phone is clamped), so it is dark in EVERY
/// frame, and it is connected to the frame's border. Dark organisms or debris inside the field
/// are not connected to the border. So: a cell is eyepiece when it was dark in nearly every
/// frame AND is joined to the border through other such cells.
struct FieldMaskBuilder {
    let width: Int
    let height: Int
    let thresholds: FieldMaskThresholds

    private let gridWidth: Int
    private let gridHeight: Int
    private var darkCounts: [Int]
    private var frames = 0

    /// - Parameters:
    ///   - width: the full frame's width in pixels.
    ///   - height: the full frame's height in pixels.
    init(width: Int, height: Int, thresholds: FieldMaskThresholds = .init()) {
        self.width = width
        self.height = height
        self.thresholds = thresholds
        gridWidth = width / max(thresholds.gridStep, 1)
        gridHeight = height / max(thresholds.gridStep, 1)
        darkCounts = [Int](repeating: 0, count: gridWidth * gridHeight)
    }

    var isComplete: Bool { frames >= thresholds.framesToLearn }

    var progress: Double {
        guard thresholds.framesToLearn > 0 else { return 1 }
        return min(Double(frames) / Double(thresholds.framesToLearn), 1)
    }

    /// Adds one downsampled frame. A grid of the wrong size is ignored.
    mutating func add(luma: [UInt8], gridWidth: Int, gridHeight: Int) {
        guard !isComplete, gridWidth == self.gridWidth, gridHeight == self.gridHeight,
            luma.count >= gridWidth * gridHeight
        else { return }
        let cut = Self.darkCut(
            of: luma, count: gridWidth * gridHeight, minRatio: thresholds.minContrastRatio,
            scale: thresholds.cutScale)
        for index in 0..<(gridWidth * gridHeight) where Double(luma[index]) < cut {
            darkCounts[index] += 1
        }
        frames += 1
    }

    /// nil until `framesToLearn` frames have been added.
    func result() -> FieldMask? {
        guard isComplete, gridWidth > 0, gridHeight > 0 else { return nil }
        let needed = Int((thresholds.alwaysDarkShare * Double(frames)).rounded(.up))
        let alwaysDark = darkCounts.map { $0 >= needed }
        let eyepiece = Self.solidField(
            eyepiece: Self.connectedToBorder(alwaysDark, width: gridWidth, height: gridHeight),
            width: gridWidth, height: gridHeight)

        let openCount = eyepiece.filter { !$0 }.count
        let openShare = Double(openCount) / Double(eyepiece.count)
        let rect: CGRect?
        if openCount == eyepiece.count {
            // The field fills the frame: everything, less the inset.
            rect = shrunk(x: 0, y: 0, w: Double(width), h: Double(height))
        } else if let cells = Self.largestRectangle(
            open: eyepiece.map { !$0 }, width: gridWidth, height: gridHeight)
        {
            let step = Double(thresholds.gridStep)
            rect = shrunk(
                x: Double(cells.x) * step, y: Double(cells.y) * step,
                w: Double(cells.width) * step, h: Double(cells.height) * step)
        } else {
            rect = nil
        }
        return FieldMask(
            gridWidth: gridWidth, gridHeight: gridHeight, gridStep: thresholds.gridStep,
            eyepiece: eyepiece, openShare: openShare,
            registrationRect: openShare >= thresholds.minOpenShare ? rect : nil)
    }

    // MARK: - Pieces

    /// The always-dark cells joined to the grid's border through 4-neighbours.
    static func connectedToBorder(_ dark: [Bool], width: Int, height: Int) -> [Bool] {
        var connected = [Bool](repeating: false, count: dark.count)
        var queue: [Int] = []
        func visit(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let index = y * width + x
            guard dark[index], !connected[index] else { return }
            connected[index] = true
            queue.append(index)
        }
        for x in 0..<width {
            visit(x, 0)
            visit(x, height - 1)
        }
        for y in 0..<height {
            visit(0, y)
            visit(width - 1, y)
        }
        var next = 0
        while next < queue.count {
            let index = queue[next]
            next += 1
            let x = index % width
            let y = index / width
            visit(x - 1, y)
            visit(x + 1, y)
            visit(x, y - 1)
            visit(x, y + 1)
        }
        return connected
    }

    /// The largest axis-aligned rectangle of open cells, by area: the standard histogram and
    /// stack method, one pass per row. The first of equal areas wins.
    static func largestRectangle(open: [Bool], width: Int, height: Int)
        -> (x: Int, y: Int, width: Int, height: Int)?
    {
        var heights = [Int](repeating: 0, count: width)
        var best: (area: Int, x: Int, y: Int, width: Int, height: Int)?
        for row in 0..<height {
            for column in 0..<width {
                heights[column] = open[row * width + column] ? heights[column] + 1 : 0
            }
            var stack: [Int] = []
            for column in 0...width {
                let current = column == width ? 0 : heights[column]
                while let top = stack.last, heights[top] >= current {
                    stack.removeLast()
                    let barHeight = heights[top]
                    let left = stack.last.map { $0 + 1 } ?? 0
                    let barWidth = column - left
                    let area = barHeight * barWidth
                    if barHeight > 0, area > (best?.area ?? 0) {
                        best = (area, left, row - barHeight + 1, barWidth, barHeight)
                    }
                }
                stack.append(column)
            }
        }
        return best.map { ($0.x, $0.y, $0.width, $0.height) }
    }

    /// Automatic (Otsu) split of a frame's luma into dark and bright; cells below the returned
    /// value are dark. 0 (nothing is dark) when the two sides are not clearly different, so an
    /// evenly lit frame has no dark part. Adapts to the slide's stain and the exposure, unlike
    /// a fixed share of the brightest pixels.
    static func darkCut(
        of values: [UInt8], count: Int, minRatio: Double, scale: Double = 1
    ) -> Double {
        guard count > 0 else { return 0 }
        var histogram = [Double](repeating: 0, count: 256)
        for index in 0..<count { histogram[Int(values[index])] += 1 }
        guard let split = otsuCut(histogram: histogram, minRatio: minRatio) else { return 0 }
        // Part of the way from the dark side's mean up to the automatic cut.
        return split.meanLow + scale * (split.cut - split.meanLow)
    }

    private static func otsuCut(histogram: [Double], minRatio: Double)
        -> (cut: Double, meanLow: Double)?
    {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return nil }
        let sumAll = histogram.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element }
        var weightLow = 0.0
        var sumLow = 0.0
        var bestVariance = -1.0
        var bestCut = 0
        var bestRatio = 0.0
        var bestMeanLow = 0.0
        for level in 0..<255 {
            weightLow += histogram[level]
            sumLow += Double(level) * histogram[level]
            let weightHigh = total - weightLow
            guard weightLow > 0, weightHigh > 0 else { continue }
            let meanLow = sumLow / weightLow
            let meanHigh = (sumAll - sumLow) / weightHigh
            let variance = weightLow * weightHigh * (meanLow - meanHigh) * (meanLow - meanHigh)
            if variance > bestVariance {
                bestVariance = variance
                bestCut = level + 1
                bestRatio = meanHigh / max(meanLow, 1)
                bestMeanLow = meanLow
            }
        }
        return bestRatio >= minRatio ? (Double(bestCut), bestMeanLow) : nil
    }

    /// Makes the open part one solid shape: only the largest connected open region is kept
    /// (stray bright specks in the ring are not the field), and holes in it are filled (a cell
    /// inside both its row's and its column's span of that region is open). The field is a
    /// disc, so this recovers a dark patch of the slide inside it.
    static func solidField(eyepiece: [Bool], width: Int, height: Int) -> [Bool] {
        var label = [Int](repeating: -1, count: eyepiece.count)
        var sizes: [Int] = []
        for start in 0..<eyepiece.count where !eyepiece[start] && label[start] < 0 {
            let id = sizes.count
            var stack = [start]
            label[start] = id
            var size = 0
            while let index = stack.popLast() {
                size += 1
                let x = index % width
                let y = index / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let neighbour = ny * width + nx
                    if !eyepiece[neighbour], label[neighbour] < 0 {
                        label[neighbour] = id
                        stack.append(neighbour)
                    }
                }
            }
            sizes.append(size)
        }
        guard let biggest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return eyepiece }

        var rowSpan = [(min: Int, max: Int)](repeating: (Int.max, -1), count: height)
        var columnSpan = [(min: Int, max: Int)](repeating: (Int.max, -1), count: width)
        for index in 0..<eyepiece.count where label[index] == biggest {
            let x = index % width
            let y = index / width
            rowSpan[y] = (min(rowSpan[y].min, x), max(rowSpan[y].max, x))
            columnSpan[x] = (min(columnSpan[x].min, y), max(columnSpan[x].max, y))
        }
        var result = [Bool](repeating: true, count: eyepiece.count)
        for y in 0..<height {
            for x in 0..<width
            where x >= rowSpan[y].min && x <= rowSpan[y].max
                && y >= columnSpan[x].min && y <= columnSpan[x].max
            {
                result[y * width + x] = false
            }
        }
        return result
    }

    /// Shrinks by the inset on each side, rounds inwards to whole pixels and keeps it inside
    /// the frame. nil when nothing is left. Whole pixels because a fractional origin made
    /// Vision's registration read 0.
    private func shrunk(x: Double, y: Double, w: Double, h: Double) -> CGRect? {
        let left = max((x + thresholds.insetShare * w).rounded(.up), 0)
        let top = max((y + thresholds.insetShare * h).rounded(.up), 0)
        let right = min((x + w - thresholds.insetShare * w).rounded(.down), Double(width))
        let bottom = min((y + h - thresholds.insetShare * h).rounded(.down), Double(height))
        guard right > left, bottom > top else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
