import SwiftUI

/// What a test is of, asked for before the guided scan opens. The date is today's and is shown
/// rather than asked, because a test is filled in as it is taken.
struct NewTestView: View {
    @Binding var details: SampleDetails
    /// "No farm" can be chosen, and is until a farm is: the operator's own sample, which is named.
    var allowsNoFarm = false
    /// Called when the helper taps Start. The caller closes this and opens the guided scan.
    var start: () -> Void

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    @State private var isShowingPreparation = false

    private enum Field {
        case name, note
    }

    private var farmText: String {
        if let id = details.farmID { return store.farms.first { $0.id == id }?.name ?? details.sampleID }
        return allowsNoFarm ? "No farm" : "Choose a farm"
    }

    private var isOwnSample: Bool { allowsNoFarm && details.farmID == nil }

    /// An own sample needs only its name; any other test must lead back to a place.
    private var canStart: Bool {
        isOwnSample
            ? !details.sampleID.trimmingCharacters(in: .whitespaces).isEmpty : details.isComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(
                        "Date", value: details.recordedAt.formatted(date: .long, time: .omitted))
                }

                Section("Farm") {
                    NavigationLink {
                        FarmChoiceList(details: $details, allowsNoFarm: allowsNoFarm)
                    } label: {
                        Text(farmText)
                            .foregroundStyle(
                                allowsNoFarm || details.farmID != nil ? .primary : .secondary)
                    }
                    // Taken from the farm, so it is shown and not typed.
                    if details.farmID != nil, let location = details.location {
                        LabeledContent("Location", value: location)
                    }
                    if details.plotID != nil, let plot = details.plotName {
                        LabeledContent("Plot", value: plot)
                    }
                }

                if isOwnSample {
                    Section {
                        TextField("Sample name", text: $details.sampleID)
                            .focused($focus, equals: .name)
                    } footer: {
                        Text("Kept on this phone. Only tests of a farm can be uploaded.")
                    }
                }

                Section("Description") {
                    TextField("Description…", text: $details.note.orEmpty, axis: .vertical)
                        .focused($focus, equals: .note)
                        .lineLimit(4...)
                }

                // The guide fixes the amounts the sample records, so it stays one tap
                // from the only screen that opens a test.
                Section {
                    Button {
                        isShowingPreparation = true
                    } label: {
                        Label("How to prepare the sample", systemImage: "testtube.2")
                    }
                }
            }
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .navigationTitle("New Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            // The operator makes the slide themselves here, so the flow includes the section
            // for it and its bar counts three.
            .sheet(isPresented: $isShowingPreparation) {
                PreparationFlow(preparingSample: true) { isShowingPreparation = false }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canStart)
                .padding()
                .background(.bar)
            }
        }
    }
}

extension Binding where Value == String? {
    /// A text field needs somewhere to put an empty string, and the details keep nil for a
    /// field nobody filled in.
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview {
    NewTestView(details: .constant(.blank)) {}
        .environment(FarmStore(fileURL: nil))
}
