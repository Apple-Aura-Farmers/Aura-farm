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
            } header: {
                Text("Step 1")
            } footer: {
                Text("Mix the sample, make the slide and mount the phone before you start.")
            }

            Section("Step 2 · Sample") {
                TextField("Name", text: $details.sampleID)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Location", text: $details.location.orEmpty)
                    .textInputAutocapitalization(.words)
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
                    sampleID: "Pak Wayan",
                    location: "Tabanan",
                    note: nil,
                    field: 1,
                    moisture: .drained,
                    gramsOfSoil: 10,
                    millilitresScanned: 0.5,
                    recordedAt: .now
                )
            ))
    }
}
