import SwiftUI

/// Sending the sweep to the Mac, and looking through its frames. Needs a sweep on disk, so
/// a made-up result shows none of it.
struct ResultActions: View {
    let sweep: SavedSweep

    /// The soil report file for the share sheet. nil while it is being written, and for a
    /// sweep that has nothing to send, which `reportProblem` then explains.
    @State private var reportURL: URL?
    @State private var reportProblem: String?

    var body: some View {
        Section {
            sendButton
        } footer: {
            Text(
                "AirDrop it to the office Mac and open it there with Aura Farm Manager, or "
                    + "save it to Files and import it on the Mac."
            )
        }
        .task(id: sweep.id) { await prepareReport() }

        Section {
            NavigationLink {
                SweepDetailView(sweep: sweep)
            } label: {
                Label("Look through the frames", systemImage: "square.grid.3x3")
            }
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if let reportURL {
            ShareLink(item: reportURL) {
                Label("Send to Mac", systemImage: "laptopcomputer.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else if let reportProblem {
            Text(reportProblem)
                .foregroundStyle(.secondary)
        } else {
            ProgressView("Preparing the report")
        }
    }

    /// Off the main thread: the report can carry the panorama, which is a few MB.
    private func prepareReport() async {
        let sweep = sweep
        let result = await Task.detached(priority: .userInitiated) {
            Result { try SoilReportExporter.writeTemporaryFile(for: sweep) }
        }.value
        switch result {
        case .success(let url):
            reportURL = url
        case .failure(let error):
            reportProblem = error.localizedDescription
        }
    }
}
