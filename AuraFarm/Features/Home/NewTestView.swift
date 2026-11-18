import SwiftUI

/// What a test is of, asked for before the guided scan opens. The date is today's and is shown
/// rather than asked, because a test is filled in as it is taken.
struct NewTestView: View {
    @Binding var details: SampleDetails
    /// Called when the helper taps Start. The caller closes this and opens the guided scan.
    var start: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field {
        case note
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
                        FarmChoiceList(details: $details)
                    } label: {
                        Text(details.sampleID.isEmpty ? "Choose a farm" : details.sampleID)
                            .foregroundStyle(details.sampleID.isEmpty ? .secondary : .primary)
                    }
                    // Taken from the farm, so it is shown and not typed.
                    if details.farmID != nil, let location = details.location {
                        LabeledContent("Location", value: location)
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
                    NavigationLink {
                        SamplePrepView()
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
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!details.isComplete)
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
