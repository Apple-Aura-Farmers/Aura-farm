import Foundation

/// Where a preset column ends: after THREE stops in a row with no sample in view, once the column
/// has shown sample. A stop is blank when the view was blank (or nothing to follow, and not
/// blurry) for the whole stop; a blurry stop is never blank, and a sample or thin view resets the
/// count. A column that never shows sample runs to its limit.
struct StagePresetEdgeWatch {
    static let blankStops = 3

    private var sawSample = false
    private var blankInRow = 0
    private var stopIsBlank = true
    private var seenInStop = false

    /// A new column: nothing seen yet.
    mutating func newColumn() { self = StagePresetEdgeWatch() }

    /// The stage stops at a spot.
    mutating func beginStop() {
        stopIsBlank = true
        seenInStop = false
    }

    /// What the view shows during the stop (called on every reading of it).
    mutating func observe(isSample: Bool, isBlank: Bool) {
        seenInStop = true
        if isSample {
            sawSample = true
            blankInRow = 0
        }
        if !isBlank { stopIsBlank = false }
    }

    /// The stop is over. True when this was the third blank stop in a row after sample.
    mutating func endStop() -> Bool {
        defer { seenInStop = false }
        guard seenInStop else { return false }
        guard stopIsBlank else {
            blankInRow = 0
            return false
        }
        blankInRow += 1
        guard sawSample, blankInRow >= Self.blankStops else { return false }
        blankInRow = 0
        return true
    }
}
