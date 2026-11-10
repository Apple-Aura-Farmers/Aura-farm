import Foundation

/// Where a sample's advice is kept. A protocol so the screen can be tested, and shown in the
/// gallery, without touching the disk.
protocol AdviceStore: Sendable {
    func load(for sweep: SavedSweep) -> SavedAdvice?
    func save(_ advice: SavedAdvice, for sweep: SavedSweep) throws
}
