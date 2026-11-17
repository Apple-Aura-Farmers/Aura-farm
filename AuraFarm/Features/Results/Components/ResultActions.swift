import SwiftUI

/// Publishing the test to the farm's records, and looking through its frames. Needs a sweep
/// on disk, so a made-up result shows none of it.
struct ResultActions: View {
    let sweep: SavedSweep

    var body: some View {
        Section {
            PublishResultButton(sweep: sweep)
        } footer: {
            Text("The farm manager reads published tests in the farm's records.")
        }

        Section {
            NavigationLink {
                SweepDetailView(sweep: sweep)
            } label: {
                Label("Look through the frames", systemImage: "square.grid.3x3")
            }
        }
    }
}
