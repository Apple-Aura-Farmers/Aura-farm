import MapKit
import SwiftUI

/// The Field Helper's screens: the land on a map, and the farmers as a list.
///
/// The search button is a tab given the search role, which is how the system draws it as its own
/// circle at the trailing end of the bar. Adding land is a button at the top of the map.
struct FieldHelperTabs: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @Environment(FarmStore.self) private var store

    @State private var screen: Screen = .plots
    /// The screen the search tab was opened from, which decides what it searches.
    @State private var searchedFrom: Screen = .plots
    /// Where the map is looking, shared by both copies of it. Held here rather than in the map
    /// screen so that switching to the search tab, or back, leaves the land where it was.
    @State private var camera: MapCameraPosition = .automatic
    /// Asked for so the map can open where the helper is standing.
    @State private var location = LocationProvider()
    /// Whether the map has been put somewhere real yet. Once it has, nothing here moves it
    /// again: a pull finishing, or a plot being reshaped, must not drag the land back off
    /// whatever the helper has since searched for or tapped.
    @State private var hasPlacedCamera = false

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

            // The circle at the end, a search of the map, or of the farmers from the other screens.
            Tab("Search", systemImage: "magnifyingglass", value: Screen.search, role: .search) {
                if searchedFrom == .plots {
                    FieldHelperHomeView(camera: $camera, isSearch: true)
                } else {
                    FarmersListView(isSearch: true)
                }
            }
        }
        .onChange(of: screen) { old, new in
            if new == .search { searchedFrom = old }
        }
        // The selected tab takes the accent, which the bar does not pick up from the app.
        .tint(.aura)
        // What draws the search tab as its own circle: without it the system puts the search-role
        // tab back in the capsule with Plots and Results.
        .tabViewSearchActivation(.searchTabSelection)
        .task { location.start() }
        .onDisappear { location.stop() }
        // The map opens where the helper is standing, which is the farm they are on, rather
        // than pulled back to take in every plot they look after at once. All of their land
        // is the fallback, for a phone with location turned off.
        //
        // Here rather than on the map, so that changing tabs does not throw away where a
        // search, or a plot just filed, has sent it.
        .onChange(of: store.farms.flatMap(\.allCorners), initial: true) {
            guard !hasPlacedCamera else { return }
            camera = .userLocation(fallback: FarmsOverviewMap.fitting(store.farms))
            // Keep trying until there is land to fall back on, or a phone with location off
            // would be left on whatever it picked before the records arrived.
            hasPlacedCamera = !store.farms.flatMap(\.allCorners).isEmpty
        }
    }
}

#Preview {
    FieldHelperTabs(onSwitchRole: {})
        .environment(FarmStore(fileURL: nil))
}
