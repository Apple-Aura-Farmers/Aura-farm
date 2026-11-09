import SwiftData
import SwiftUI
import UIKit

/// One soil test: where it is filed, what was counted, the sample, and how it was counted.
///
/// The counts are raw. The screen says so, and never turns them into a rating: the plan on the
/// field's page is built from NPK results, and these counts never change a dose.
///
/// Both roles can file a test under a field and add notes: the helper usually knows which
/// field a sample came from.
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
                    Image(uiImage: panorama)
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
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filing: some View {
        Section {
            FieldPicker(selection: $test.field)
        } header: {
            Text("Filed Under")
        } footer: {
            if FieldPicker.hasNoFields(farms) {
                Text("There are no fields yet. The program manager adds farms and fields on the Farms tab.")
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
            LabeledContent("Water", value: Self.amount(test.millilitresOfWater, unit: "mL"))
            if !test.preparation.isEmpty {
                LabeledContent("Preparation", value: test.preparation)
            }
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

    private var panorama: UIImage? {
        test.panoramaJPEG.flatMap { UIImage(data: $0) }
    }

    /// "10 g", or "Not recorded" for an amount the helper left empty.
    private static func amount(_ value: Double?, unit: String) -> String {
        guard let value else { return "Not recorded" }
        return "\(value.formatted(.number)) \(unit)"
    }
}
