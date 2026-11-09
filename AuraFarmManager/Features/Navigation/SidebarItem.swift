import Foundation

/// What the sidebar can show in the middle column.
enum SidebarItem: Hashable {
    /// Soil tests not yet filed under a field.
    case inbox
    case allTests
    case farm(Farm)
    /// One field of a farm: its NPK results, soil tests and what to do about it.
    case field(Field)
}
