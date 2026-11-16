import Foundation

/// A Mark start or Mark end waiting for the next logged row.
struct PendingMark: Equatable {
    var name: String
    var millimetres: Double?
}

/// Holds at most one mark until a row is logged. A newer mark replaces an unlogged older one.
struct MarkSlot {
    private var pending: PendingMark?

    mutating func place(_ mark: PendingMark) { pending = mark }

    /// The mark for the row being written now, if any; the slot is empty afterwards.
    mutating func take() -> PendingMark? {
        defer { pending = nil }
        return pending
    }

    mutating func clear() { pending = nil }
}
