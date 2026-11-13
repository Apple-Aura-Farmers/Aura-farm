import SwiftUI

/// Looking through a sweep's frames. Needs a sweep on disk, so a made-up result shows none
/// of it.
struct ResultActions: View {
    let sweep: SavedSweep

    var body: some View {
        Section {
            NavigationLink {
                SweepDetailView(sweep: sweep)
            } label: {
                Label("Look through the frames", systemImage: "square.grid.3x3")
            }
        }
    }
}
