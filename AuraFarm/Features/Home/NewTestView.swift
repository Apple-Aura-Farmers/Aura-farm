import SwiftUI

/// What a test is of, asked for before the camera opens. The date is today's and is shown
/// rather than asked, because a test is filled in as it is taken.
struct NewTestView: View {
    @Binding var details: SampleDetails
    /// Called when the helper taps Start. The caller closes this and opens the camera.
    var start: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    @State private var isUsingRecording = false

    private enum Field {
        case note
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LabeledContent("Date") {
                        Text(details.recordedAt.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
                    }
                    .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Farm")
                            .font(.headline)
                        card {
                            NavigationLink {
                                FarmChoiceList(details: $details)
                            } label: {
                                HStack {
                                    Text(
                                        details.sampleID.isEmpty
                                            ? "Choose a farm" : details.sampleID
                                    )
                                    .foregroundStyle(details.sampleID.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // Taken from the farm, so it is shown and not typed.
                            if details.farmID != nil, let location = details.location {
                                Divider()
                                LabeledContent("Location", value: location)
                                    .font(.subheadline)
                            }
                        }
                    }

                    card {
                        TextField("Description…", text: $details.note.orEmpty, axis: .vertical)
                            .focused($focus, equals: .note)
                            .lineLimit(4...)
                    }

                    // The guide fixes the amounts the report records, so it stays one tap
                    // from the only screen that opens a test.
                    NavigationLink {
                        SamplePrepView()
                    } label: {
                        Label("How to prepare the sample", systemImage: "testtube.2")
                            .font(.subheadline)
                    }
                }
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
            }
            .navigationTitle("New Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(action: start) {
                        Text("Start")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(InvertedButtonStyle())
                    .disabled(!details.isComplete)

                    // Prototype: the same pipeline, fed from a recorded microscope video.
                    Button {
                        isUsingRecording = true
                    } label: {
                        Label("Use a recorded video", systemImage: "film")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!details.isComplete)
                }
                .padding()
                .background(.bar)
            }
            .navigationDestination(isPresented: $isUsingRecording) {
                RecordedSampleView(details: $details)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemFill)))
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
