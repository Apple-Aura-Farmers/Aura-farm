import Foundation

/// Whether the guided scan is open, and so whether the New Test sheet behind it may be dismissed.
/// From the moment the scan opens until it closes, nothing but the scan's own Close and End run
/// may take it away: a swipe down on the sheet must not cancel a run.
struct GuidedScanLaunch: Equatable {
    private(set) var isOpen = false

    /// The sheet's interactive dismissal (the swipe down) is off while the scan is open.
    var locksSheetDismissal: Bool { isOpen }

    mutating func open() { isOpen = true }
    mutating func close() { isOpen = false }
}
