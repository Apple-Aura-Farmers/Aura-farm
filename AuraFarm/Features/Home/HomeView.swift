import SwiftUI

/// Where the app opens: start a test, or look at the ones already taken.
struct HomeView: View {
    /// Sends the person back to the role picker. nil where there is no picker, as in previews.
    var onSwitchRole: (() -> Void)?

    init(onSwitchRole: (() -> Void)? = nil) {
        self.onSwitchRole = onSwitchRole
    }

    var body: some View {
        TabView {
            HomeTab(onSwitchRole: onSwitchRole)
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack {
                SweepLibraryView()
            }
            .tabItem { Label("Results", systemImage: "doc.text.image") }
        }
    }
}

/// The first tab: one button to start a test, and what the finished ones add up to.
private struct HomeTab: View {
    var onSwitchRole: (() -> Void)?

    /// Carried across the sheet and the camera, so the camera is given the details the
    /// helper just typed.
    @State private var details = SampleDetails.blank
    @State private var isNaming = false
    @State private var isRecording = false
    @State private var sweeps: [SavedSweep] = []
    @State private var isReadingNotices = false
    /// The sweep the camera just saved, to show its result.
    @State private var finishedSweep: SavedSweep?

    private var notices: [SweepNotice] { SweepNotice.all(for: sweeps) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button {
                        details = .blank
                        isNaming = true
                    } label: {
                        Label("New Test", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(InvertedButtonStyle())

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overview")
                            .font(.title3.bold())
                        overview
                    }
                }
                .padding()
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NoticesButton(notices: notices) { isReadingNotices = true }
                }
                if let onSwitchRole {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onSwitchRole) {
                            Label("Switch role", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                #if DEBUG
                    // A workbench for trying the pipeline without a microscope.
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink {
                                VideoStitchWorkbenchView()
                            } label: {
                                Label("Stitch from video", systemImage: "film")
                            }
                            NavigationLink {
                                DetectVideoView()
                            } label: {
                                Label("Detect in a sample", systemImage: "viewfinder")
                            }
                            NavigationLink {
                                DetectorBenchmarkView()
                            } label: {
                                Label("Detector speed", systemImage: "speedometer")
                            }
                            NavigationLink {
                                ResultStatesGallery()
                            } label: {
                                Label("Result states", systemImage: "list.bullet.rectangle")
                            }
                            NavigationLink {
                                AdviceCheckView()
                            } label: {
                                Label("Advice check", systemImage: "checklist")
                            }
                            NavigationLink {
                                SlideMovementLabView()
                            } label: {
                                Label("Slide movement lab", systemImage: "move.3d")
                            }
                        } label: {
                            Label("Workbench", systemImage: "hammer")
                        }
                    }
                #endif
            }
            .sheet(isPresented: $isReadingNotices) {
                NoticesView(notices: notices)
            }
            .sheet(isPresented: $isNaming) {
                NewTestView(details: $details) {
                    isNaming = false
                    isRecording = true
                }
            }
            .navigationDestination(isPresented: $isRecording) {
                CaptureView(details: $details) { name in
                    finishedSweep = SweepLibrary.sweeps().first { $0.name == name }
                }
                // Walking a slide wants the whole screen, and there is nowhere else to be
                // while the camera is open.
                .toolbar(.hidden, for: .tabBar)
            }
            .sheet(item: $finishedSweep) { sweep in
                NavigationStack {
                    SoilResultScreen(sweep: sweep)
                }
            }
            .task(id: isRecording) { sweeps = SweepLibrary.sweeps() }
        }
    }

    @ViewBuilder
    private var overview: some View {
        if sweeps.isEmpty {
            Text("Tests you take will be summed up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sweeps.count) \(sweeps.count == 1 ? "test" : "tests")")
                    .font(.headline)
                if let latest = sweeps.first {
                    Text("Latest: \(latest.manifest?.details.sampleID ?? latest.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(latest.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A filled button the other way round from the system's: the page's own colour on the
/// text's, so it reads as the one thing to do on the screen in either light or dark.
struct InvertedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color(uiColor: .systemBackground) : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isEnabled ? Color.primary : Color(uiColor: .secondarySystemFill))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension SampleDetails {
    /// A test that has not been filled in yet.
    static var blank: SampleDetails {
        SampleDetails(
            sampleID: "",
            location: nil,
            note: nil,
            field: 1,
            moisture: .drained,
            gramsOfSoil: SamplePrepView.gramsOfSoil,
            millilitresScanned: nil,
            recordedAt: .now
        )
    }
}

#Preview {
    HomeView()
}
