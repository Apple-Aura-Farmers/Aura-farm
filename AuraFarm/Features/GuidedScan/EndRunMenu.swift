import Foundation

/// The End run menu in the page's top bar: what it offers and what each choice does. A menu, not
/// a dialog, so it cannot clash with "Stop this scan?".
enum EndRunMenu {
    enum Item: Equatable {
        case endNow, endAfterColumn
        /// Take back "End after this column".
        case undo
        case keepScanning

        var title: String {
            switch self {
            case .endNow: "End now"
            case .endAfterColumn: "End after this column"
            case .undo: "Keep going (cancel ending)"
            case .keepScanning: "Keep scanning"
            }
        }

        /// What the engine is told; nil for "Keep scanning", which does nothing.
        var action: EndRunAction? {
            switch self {
            case .endNow: .now
            case .endAfterColumn: .afterColumn
            case .undo: .cancel
            case .keepScanning: nil
            }
        }
    }

    /// While ending after the column, the way to undo; otherwise End now, and End after this
    /// column only while a column is being swept.
    static func items(columnInProgress: Bool, endingAfterColumn: Bool) -> [Item] {
        if endingAfterColumn { return [.undo, .endNow, .keepScanning] }
        return (columnInProgress ? [.endNow, .endAfterColumn] : [.endNow]) + [.keepScanning]
    }

    /// While the stage is away from the path (steered by hand, returning, or a saved position
    /// waits): the column cannot be ended after, only the run now.
    static let awayItems: [Item] = [.endNow, .keepScanning]

    /// The button's words: it says at once what was chosen.
    static func label(endingAfterColumn: Bool) -> String {
        endingAfterColumn ? "Ending after this column" : "End run"
    }
}
