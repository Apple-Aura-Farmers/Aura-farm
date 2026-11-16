import SwiftUI

/// The Field Helper's two screens: the land on a map, and the farmers as a list.
///
/// Searching lives on each screen rather than in the bar: the map carries a field for places
/// and farmers along its top, and the farmers list has the system's own search. That leaves
/// the bar as the mockup has it, with the button for marking new land beside it.
struct FieldHelperTabs: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @State private var screen: Screen = .plots

    private enum Screen: Hashable {
        case plots, results
    }

    var body: some View {
        TabView(selection: $screen) {
            Tab(
                "Plots", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                value: Screen.plots
            ) {
                FieldHelperHomeView()
            }

            Tab("Results", systemImage: "doc.text", value: Screen.results) {
                FarmersListView(onSwitchRole: onSwitchRole)
            }
        }
    }
}

#Preview {
    FieldHelperTabs(onSwitchRole: {})
        .environment(FarmStore(fileURL: nil))
}
