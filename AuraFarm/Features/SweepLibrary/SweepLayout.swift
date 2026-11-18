import SwiftUI

/// Where each frame of a sweep sits on the slide. The rows alternate direction, so the
/// slide is only ever nudged on from where it already is rather than carried back to the
/// start of the next row.
///
/// Shared by the diagram in the guide and by the grid a saved sweep is laid out in, so the
/// two cannot drift apart.
struct SweepLayout {
    var columns: Int
    var rows: Int

    init(thresholds: SweepThresholds = SweepThresholds(), frameCount: Int? = nil) {
        columns = max(thresholds.framesPerRow, 1)
        let frames = max(frameCount ?? thresholds.framesPerSweep, 1)
        // A sweep that stopped early has a part row at the end, which still needs a row.
        rows = Int((Double(frames) / Double(columns)).rounded(.up))
    }

    func position(of index: Int) -> (row: Int, column: Int) {
        let row = index / columns
        let along = index % columns
        return (row: row, column: row.isMultiple(of: 2) ? along : columns - 1 - along)
    }

    /// The frame indices of one row, in the order the slide passes through them.
    func indices(inRow row: Int, frameCount: Int) -> [Int] {
        let start = row * columns
        let indices = (start..<min(start + columns, frameCount)).map { $0 }
        return row.isMultiple(of: 2) ? indices : indices.reversed()
    }
}
