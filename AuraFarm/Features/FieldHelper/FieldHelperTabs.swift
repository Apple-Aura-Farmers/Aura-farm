import SwiftUI

/// The Field Helper's screens: the land on a map, the farmers as a list, and the search beside
/// them.
///
/// Search is a tab with the search role, which is what draws it as its own round button to the
/// right of the bar in the mockup. Tapping it is the system's own move: the bar shrinks out of
/// the way to the left and the field grows into the space it leaves. Nothing here animates
/// that; it comes with the role.
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
                FieldHelperHomeView(onSwitchRole: onSwitchRole)
            }

            Tab("Results", systemImage: "doc.text", value: Screen.results) {
                FarmersListView()
            }

            Tab(value: Screen.search, role: .search) {
                FarmersListView(isSearch: true)
            }
        }
    }
}

#Preview {
    FieldHelperTabs(onSwitchRole: {})
        .environment(
            FarmStore(
                fileURL: nil,
                farms: [
                    Farm(
                        name: "Pak Wayan", farmerName: "Pak Wayan",
                        plots: [
                            Plot(
                                name: "Tabanan",
                                corners: [
                                    GeoPoint(latitude: -8.4095, longitude: 115.1889),
                                    GeoPoint(latitude: -8.4095, longitude: 115.1900),
                                    GeoPoint(latitude: -8.4105, longitude: 115.1900),
                                ])
                        ])
                ]))
}
