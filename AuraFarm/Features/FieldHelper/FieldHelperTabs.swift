import SwiftUI

/// The Field Helper's screens: the land on a map, the farmers as a list, and searching them.
///
/// The search tab is the system's own button appearance: it leaves the bar as its own circle
/// at the trailing end, and tapping it expands that circle into the field in place. The map
/// keeps a field of its own along the top, because it searches places as well as farmers,
/// which this list cannot do.
struct FieldHelperTabs: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @State private var screen: Screen = .plots

    private enum Screen: Hashable {
        case plots, results, search
    }

    var body: some View {
        TabView(selection: $screen) {
            Tab(
                "Plots", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                value: Screen.plots
            ) {
                FieldHelperHomeView(isBesideSearchButton: true)
            }

            Tab("Results", systemImage: "doc.text", value: Screen.results) {
                FarmersListView(onSwitchRole: onSwitchRole)
            }

            Tab(value: Screen.search, role: .search) {
                FarmersListView(onSwitchRole: onSwitchRole, isSearch: true)
            }
        }
        // What makes the search tab the prominent one, and so draws it as that trailing
        // circle: without it the system puts search back in the capsule as an ordinary tab.
        .tabViewSearchActivation(.searchTabSelection)
    }
}

#Preview {
    FieldHelperTabs(onSwitchRole: {})
        .environment(FarmStore(fileURL: nil))
}
