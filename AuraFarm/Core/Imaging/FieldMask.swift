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

    /// The eyepiece cells as rectangles in FULL-FRAME pixels, top-down: consecutive cells in a
    /// row are joined, and a run that repeats the one above it grows downwards. Few enough to
    /// draw one by one on the preview.
    func eyepieceRects() -> [CGRect] {
        guard gridWidth > 0, gridHeight > 0, eyepiece.count == gridWidth * gridHeight else {
            return []
        }
        struct Run: Hashable {
            var start: Int
            var length: Int
        }
        var finished: [CGRect] = []
        var open: [Run: Int] = [:]  // the run, and the row it began on
        let step = Double(gridStep)

        func close(_ run: Run, from row: Int, to endRow: Int) {
            finished.append(
                CGRect(
                    x: Double(run.start) * step, y: Double(row) * step,
                    width: Double(run.length) * step, height: Double(endRow - row) * step))
        }

        for row in 0..<gridHeight {
            var runs: [Run] = []
            var column = 0
            while column < gridWidth {
                if eyepiece[row * gridWidth + column] {
                    let start = column
                    while column < gridWidth && eyepiece[row * gridWidth + column] { column += 1 }
                    runs.append(Run(start: start, length: column - start))
                } else {
                    column += 1
                }
            }
            for (run, began) in open where !runs.contains(run) {
                close(run, from: began, to: row)
                open[run] = nil
            }
            for run in runs where open[run] == nil { open[run] = row }
        }
        for (run, began) in open { close(run, from: began, to: gridHeight) }
        return finished
    }
}
