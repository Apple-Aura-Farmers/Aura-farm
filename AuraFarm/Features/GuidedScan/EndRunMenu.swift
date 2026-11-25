import Foundation

/// The End run menu in the page's top bar: what it offers and what each choice does. A menu, not
/// a dialog, so it cannot clash with "Stop this scan?".
enum EndRunMenu {
    enum Item: Equatable {
        case endNow, endAfterColumn
        /// Take back "End after this column".
        case undo
        /// Stop without saving: asks "Stop this scan?" first, like the X. The only red item.
        case discard
        case keepScanning

        var title: String {
            switch self {
            case .endNow: "End now"
            case .endAfterColumn: "End after this column"
            case .undo: "Keep going (cancel ending)"
            case .discard: "Stop and discard"
            case .keepScanning: "Keep scanning"
            }
        }

        /// What the engine is told; nil for "Stop and discard" (the page asks first) and "Keep
        /// scanning", which does nothing.
        var action: EndRunAction? {
            switch self {
            case .endNow: .now
            case .endAfterColumn: .afterColumn
            case .undo: .cancel
            case .discard, .keepScanning: nil
            }
        }
    }

    /// While ending after the column, the way to undo; otherwise End now, and End after this
    /// column only while a column is being swept.
    static func items(columnInProgress: Bool, endingAfterColumn: Bool) -> [Item] {
        if endingAfterColumn { return [.undo, .endNow, .discard, .keepScanning] }
        return (columnInProgress ? [.endNow, .endAfterColumn] : [.endNow]) + [.discard, .keepScanning]
    }

    /// While the stage is away from the path (steered by hand, returning, or a saved position
    /// waits): the column cannot be ended after, only the run now.
    static let awayItems: [Item] = [.endNow, .discard, .keepScanning]

    /// The button's words: it says at once what was chosen.
    static func label(endingAfterColumn: Bool) -> String {
        endingAfterColumn ? "Ending after this column" : "End run"
    }
}
