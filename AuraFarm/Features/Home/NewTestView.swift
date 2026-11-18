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
    #if DEBUG
        @State private var guidedScan = GuidedScanLaunch()
    #endif

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
                VStack(spacing: 8) {
                    Button(action: start) {
                        Text("Start")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!details.isComplete)

                    // Prototype: the same pipeline, fed from a recorded microscope video.
                    Button {
                        isUsingRecording = true
                    } label: {
                        Label("Use a recorded video", systemImage: "film")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!details.isComplete)

                    #if DEBUG
                        // The guided scan for helpers: debug only until the engine is in the
                        // release app.
                        Button {
                            guidedScan.open()
                        } label: {
                            Label("Guided scan", systemImage: "scope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!details.isComplete)
                    #endif
                }
                .padding()
                .background(.bar)
            }
            .navigationDestination(isPresented: $isUsingRecording) {
                RecordedSampleView(details: $details)
            }
            #if DEBUG
                // Full screen, not pushed inside this sheet: a swipe down cannot take a run
                // away. The sheet's own swipe is off while the scan is open as well.
                .fullScreenCover(
                    isPresented: Binding(
                        get: { guidedScan.isOpen },
                        set: { if $0 { guidedScan.open() } else { guidedScan.close() } })
                ) {
                    NavigationStack { GuidedScanPage(details: $details) }
                    .interactiveDismissDisabled(true)
                }
                .interactiveDismissDisabled(guidedScan.locksSheetDismissal)
            #endif
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
