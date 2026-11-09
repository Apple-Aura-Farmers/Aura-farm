import Foundation

/// Where a sample's feedback is kept. A protocol so the screen can be tested without the disk.
protocol AdviceFeedbackStore: Sendable {
    func all(for sweep: SavedSweep) -> [AdviceFeedback]
    /// Adds the feedback, or replaces the entry with the same id.
    func record(_ feedback: AdviceFeedback, for sweep: SavedSweep) throws
}
