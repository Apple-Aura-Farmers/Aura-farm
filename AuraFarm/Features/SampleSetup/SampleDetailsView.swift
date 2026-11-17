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
                NavigationLink {
                    FarmChoiceList(details: $details)
                } label: {
                    LabeledContent(
                        "Farm", value: details.sampleID.isEmpty ? "Choose a farm" : details.sampleID)
                }
                // Taken from the farm, so it is shown and not typed.
                if details.farmID != nil, let location = details.location {
                    LabeledContent("Location", value: location)
                }
                Stepper("Microscope field \(details.field)", value: $details.field, in: 1...999)
                Picker("Soil", selection: $details.moisture) {
                    ForEach(SampleDetails.Moisture.allCases) { moisture in
                        Text(moisture.label).tag(moisture)
                    }
                }
            }

            Section {
                Picker("Crop stage", selection: $details.cropStage) {
                    Text("Not set").tag(SampleDetails.CropStage?.none)
                    ForEach(SampleDetails.CropStage.allCases) { stage in
                        Text(stage.label).tag(Optional(stage))
                    }
                }
                NavigationLink {
                    RecentActionsList(actions: $details.recentActions)
                } label: {
                    LabeledContent(
                        "Done recently",
                        value: details.recentActions.map { "\($0.count)" } ?? "None")
                }
            } header: {
                Text("Step 3 · Field notes (optional)")
            } footer: {
                Text(
                    "Samples from the same farm are compared with each other. Skip anything you don't know."
                )
            }
        }
    }
}

/// One toggle per thing done to the plot lately. An empty choice is stored as nil.
private struct RecentActionsList: View {
    @Binding var actions: [SampleDetails.RecentAction]?

    var body: some View {
        Form {
            Section {
                ForEach(SampleDetails.RecentAction.allCases) { action in
                    Toggle(action.label, isOn: isOn(action))
                }
            } footer: {
                Text("In the last two weeks.")
            }
        }
        .navigationTitle("Done recently")
    }

    private func isOn(_ action: SampleDetails.RecentAction) -> Binding<Bool> {
        Binding(
            get: { actions?.contains(action) ?? false },
            set: { on in
                // Kept in the list's own order, so the same choice always saves the same way.
                let chosen = SampleDetails.RecentAction.allCases.filter {
                    $0 == action ? on : actions?.contains($0) ?? false
                }
                actions = chosen.isEmpty ? nil : chosen
            }
        )
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
                    recordedAt: .now,
                    plotName: "North 2",
                    cropStage: .tillering,
                    recentActions: [.fertilized]
                )
            ))
    }
    .environment(FarmStore(fileURL: nil))
}
