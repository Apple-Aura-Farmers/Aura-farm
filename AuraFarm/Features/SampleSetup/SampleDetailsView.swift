import SwiftUI

/// The form for what a clip is of. Shown on its own before the camera opens, and again
/// from the options menu when the sample changes.
struct SampleDetailsView: View {
    @Binding var details: SampleDetails

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    SamplePrepView()
                } label: {
                    Label("How to prepare the sample", systemImage: "testtube.2")
                }
            }

            Section("Sample") {
                TextField("Sample ID", text: $details.sampleID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Stepper("Field \(details.field)", value: $details.field, in: 1...999)
                Picker("Soil", selection: $details.moisture) {
                    ForEach(SampleDetails.Moisture.allCases) { moisture in
                        Text(moisture.label).tag(moisture)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SampleDetailsView(
            details: .constant(
                SampleDetails(
                    sampleID: "A12",
                    field: 1,
                    moisture: .drained,
                    gramsOfSoil: 10,
                    millilitresScanned: 0.5,
                    recordedAt: .now
                )
            ))
    }
}
