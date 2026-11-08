import AuraFarmKit
import SwiftUI

/// What one sweep counted, with the button that sends it to the farm manager on the Mac.
///
/// Shown when a sweep finishes, from the camera or from a recorded video. The counts are raw:
/// the screen says so and gives no verdict on the soil, because a verdict needs recommended
/// actions behind it and those are not built yet.
struct SoilTestResultView: View {
    let sweep: SavedSweep

    @Environment(\.dismiss) private var dismiss
    /// The soil report file for the share sheet. nil while it is being written, and for a
    /// sweep that has nothing to send, which `reportProblem` then explains.
    @State private var reportURL: URL?
    @State private var reportProblem: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Sample", value: details?.sampleID ?? sweep.name)
                LabeledContent("Recorded") {
                    Text(sweep.recordedAt, format: .dateTime.day().month().hour().minute())
                }
                LabeledContent("Frames kept", value: "\(sweep.frameCount)")
            }

            Section {
                organismRows
            } header: {
                Text("Organisms counted")
            } footer: {
                Text(
                    "Raw counts from this sweep. Compare them only with tests prepared the same "
                        + "way. They are not a soil health rating."
                )
            }

            Section {
                sendButton
            } footer: {
                Text(
                    "AirDrop it to the office Mac and open it there with Aura Farm Manager, or "
                        + "save it to Files and import it on the Mac."
                )
            }

            Section {
                NavigationLink {
                    SweepDetailView(sweep: sweep)
                } label: {
                    Label("Look through the frames", systemImage: "square.grid.3x3")
                }
            }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await prepareReport() }
    }

    private var details: SampleDetails? { sweep.manifest?.details }

    /// One organism group and how many of it were counted.
    private struct GroupCount: Identifiable {
        var taxon: String
        var count: Int
        var id: String { taxon }
    }

    /// Most counted first, the same order the Mac shows them in. nil when the sweep was not
    /// counted at all.
    private var counts: [GroupCount]? {
        sweep.manifest?.organismCounts.map { counts in
            counts
                .filter { $0.value > 0 }
                .map { GroupCount(taxon: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.taxon < $1.taxon }
        }
    }

    @ViewBuilder
    private var organismRows: some View {
        if let counts {
            if counts.isEmpty {
                Text(
                    "No organisms were counted. An empty slide usually means a sampling problem, "
                        + "not empty soil: check the preparation and try again."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(counts) { organism in
                    LabeledContent {
                        Text(organism.count, format: .number)
                            .font(.title3.monospacedDigit().bold())
                    } label: {
                        Text(OrganismGroup.commonName(forTaxon: organism.taxon))
                        Text(organism.taxon)
                            .italic()
                    }
                }
                LabeledContent("Total") {
                    Text(counts.reduce(0) { $0 + $1.count }, format: .number)
                        .monospacedDigit()
                }
            }
        } else {
            Text("This sweep was not counted: the detector could not open.")
                .foregroundStyle(.secondary)
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
