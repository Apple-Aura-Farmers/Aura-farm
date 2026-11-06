import AppKit
import SwiftData
import SwiftUI

/// One soil test: where it is filed, what was counted, the sample, and how it was counted.
///
/// The counts are raw. The screen says so, and never turns them into a rating: a result a
/// farmer acts on needs recommended actions behind it, which this app does not give yet.
struct SoilTestDetailView: View {
    @Bindable var test: SoilTest

    @Query(sort: \Farm.name) private var farms: [Farm]

    var body: some View {
        Form {
            filing
            counts
            sample
            method
            if let panorama {
                Section("Slide") {
                    Image(nsImage: panorama)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                }
            }
            Section("Notes") {
                TextField("Notes", text: $test.notes, axis: .vertical)
                    .lineLimit(3...10)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(test.sampleID)
    }

    private var filing: some View {
        Section {
            Picker("Field", selection: $test.field) {
                Text("Unassigned").tag(Field?.none)
                ForEach(farms) { farm in
                    Section(farm.name) {
                        ForEach(farm.sortedFields) { field in
                            Text(field.name).tag(Field?.some(field))
                        }
                    }
                }
            }
        } header: {
            Text("Filed Under")
        } footer: {
            if farms.allSatisfy(\.fields.isEmpty) {
                Text("Add a farm and its fields in the sidebar to file this test.")
            }
        }
    }

    private var counts: some View {
        Section {
            if test.organismCounts.isEmpty {
                Text(
                    "No organisms were counted. An empty slide usually means a sampling problem, "
                        + "not empty soil: check the preparation and test again."
                )
                .foregroundStyle(.secondary)
            } else {
                OrganismCountChart(counts: test.sortedCounts)
                ForEach(test.sortedCounts) { organism in
                    LabeledContent {
                        Text(organism.count, format: .number)
                            .monospacedDigit()
                    } label: {
                        Text(organism.commonName)
                        Text(organism.taxon)
                            .italic()
                    }
                }
                LabeledContent("Total") {
                    Text(test.totalCount, format: .number)
                        .monospacedDigit()
                        .bold()
                }
            }
        } header: {
            Text("Organisms Counted")
        } footer: {
            Text(
                "Raw counts from \(test.frameCount) frames. Compare them only between tests "
                    + "prepared the same way. They are not a soil health rating."
            )
        }
    }

    private var sample: some View {
        Section("Sample") {
            LabeledContent("Sample ID", value: test.sampleID)
            LabeledContent("Recorded") {
                Text(test.recordedAt, format: .dateTime.day().month().year().hour().minute())
            }
            LabeledContent("Soil", value: test.moistureLabel)
            LabeledContent("Soil used", value: Self.amount(test.gramsOfSoil, unit: "g"))
            LabeledContent("Extract scanned", value: Self.amount(test.millilitresScanned, unit: "mL"))
            LabeledContent("Microscope field", value: "\(test.microscopeField)")
        }
    }

    private var method: some View {
        Section("How It Was Counted") {
            LabeledContent(
                "Frames",
                value: test.stoppedEarly
                    ? "\(test.frameCount), stopped at the size limit" : "\(test.frameCount)"
            )
            LabeledContent("Detector", value: test.detectorModel)
            LabeledContent("Field app", value: test.fieldAppVersion)
            LabeledContent("Imported") {
                Text(test.importedAt, format: .dateTime.day().month().year().hour().minute())
            }
        }
    }

    private var panorama: NSImage? {
        test.panoramaJPEG.flatMap { NSImage(data: $0) }
    }

    /// "10 g", or "Not recorded" for an amount the helper left empty.
    private static func amount(_ value: Double?, unit: String) -> String {
        guard let value else { return "Not recorded" }
        return "\(value.formatted(.number)) \(unit)"
    }
}
