import AuraFarmKit
import SwiftData
import SwiftUI

/// What one sweep counted, saved into the farm records the program manager works from.
///
/// Shown when a sweep finishes, from the camera or from a recorded video. The test is saved as
/// soon as the screen opens, so nothing depends on remembering a button; the helper then
/// picks the field it came from, and the field's plan is one tap away to explain to the
/// farmer. The counts are raw: the screen says so and gives no verdict on the soil.
struct SoilTestResultView: View {
    let sweep: SavedSweep

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// The soil test this sweep became in the records. nil until saved, or when it cannot be.
    @State private var savedTest: SoilTest?
    @State private var saveProblem: String?
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
                recordsRows
            } header: {
                Text("Farm records")
            } footer: {
                Text(
                    "Saved on this phone for the program manager. Pick the field the sample came "
                        + "from; until then it waits in the manager's inbox."
                )
            }

            Section {
                sendButton
            } footer: {
                Text("Only needed to move the test to another phone, or to keep a copy in Files.")
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
        .task { saveToRecords() }
    }

    @ViewBuilder
    private var recordsRows: some View {
        if let savedTest {
            FieldPicker(selection: fieldBinding(for: savedTest))
            if let field = savedTest.field {
                NavigationLink {
                    FieldDetailView(field: field)
                        .farmRecordDestinations()
                } label: {
                    Label("What to do on \(field.name)", systemImage: "list.bullet.clipboard")
                }
            }
        } else if let saveProblem {
            Text(saveProblem)
                .foregroundStyle(.secondary)
        } else {
            ProgressView("Saving")
        }
    }

    /// Filing changes the test and is saved straight away, so leaving the screen keeps it.
    private func fieldBinding(for test: SoilTest) -> Binding<Field?> {
        Binding(
            get: { test.field },
            set: { field in
                test.field = field
                try? modelContext.save()
            }
        )
    }

    /// Saving twice finds the same test again, so reopening a result does not double it.
    private func saveToRecords() {
        do {
            switch try SoilReportImporter(context: modelContext).importSweep(sweep) {
            case .imported(let test), .alreadyImported(let test):
                savedTest = test
            }
        } catch {
            saveProblem = error.localizedDescription
        }
    }

    private var details: SampleDetails? { sweep.manifest?.details }

    /// One organism group and how many of it were counted.
    private struct GroupCount: Identifiable {
        var taxon: String
        var count: Int
        var id: String { taxon }
    }

    /// Most counted first, the same order the records show them in. nil when the sweep was not
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
                Label("Share Report", systemImage: "square.and.arrow.up")
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
