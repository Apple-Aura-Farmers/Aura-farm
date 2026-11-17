import MapKit
import SwiftUI

/// The Field Helper's screens: the land on a map, the farmers as a list, and searching them.
///
/// The search tab is the system's own button appearance: it leaves the bar as its own circle
/// at the trailing end, and tapping it expands that circle into the field in place. That tab
/// shows the same map as the Plots tab, looking at the same place, so expanding the field
/// does not take the land off the screen.
struct FieldHelperTabs: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @Environment(FarmStore.self) private var store

    @State private var screen: Screen = .plots
    /// Where the map is looking, shared by both copies of it. Held here rather than in the map
    /// screen so that switching to the search tab, or back, leaves the land where it was.
    @State private var camera: MapCameraPosition = .automatic

    private enum Screen: Hashable {
        case plots, results, search
    }

    var body: some View {
        TabView(selection: $screen) {
            Tab(
                "Plots", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                value: Screen.plots
            ) {
                FieldHelperHomeView(camera: $camera)
            }

            Tab("Results", systemImage: "doc.text", value: Screen.results) {
                FarmersListView(onSwitchRole: onSwitchRole)
            }

            Tab(value: Screen.search, role: .search) {
                FieldHelperHomeView(camera: $camera, isSearch: true)
            }
        }
        // What makes the search tab the prominent one, and so draws it as that trailing
        // circle: without it the system puts search back in the capsule as an ordinary tab.
        .tabViewSearchActivation(.searchTabSelection)
        // Fits the land when the tabs appear and whenever land is added, deleted or reshaped.
        // Here rather than on the map, so that changing tabs does not throw away where a
        // search has just sent it.
        .onChange(of: store.farms.flatMap(\.allCorners), initial: true) {
            camera = FarmsOverviewMap.fitting(store.farms)
        }
    }
}

#Preview {
    FieldHelperTabs(onSwitchRole: {})
        .environment(FarmStore(fileURL: nil))
}
