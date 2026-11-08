import Foundation

/// What the sidebar can show in the middle column.
enum SidebarItem: Hashable {
    /// Soil tests not yet filed under a field.
    case inbox
    case allTests
    case farm(Farm)
}
