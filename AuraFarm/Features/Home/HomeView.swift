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
    /// The guided scan is open (full screen). Set once the New Test sheet has closed.
    @State private var isScanning = false
    /// Start was tapped: the guided scan opens as soon as the New Test sheet is gone.
    @State private var startRequested = false
    /// What the scan saved, shown on the results screen once the scan has closed.
    @State private var savedName: String?
    @State private var sweeps: [SavedSweep] = []
    @State private var isReadingNotices = false
    @State private var isShowingAccount = false
    /// The sweep the camera just saved, to show its result.
    @State private var finishedSweep: SavedSweep?

    private var notices: [SweepNotice] { SweepNotice.all(for: sweeps) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        details = .blank
                        isNaming = true
                    } label: {
                        Label("New Test", systemImage: "plus")
                            // A list tints a label's icon with the accent colour, which
                            // would sink it into the filled button.
                            .foregroundStyle(Color.auraOnAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Overview") {
                    overview
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NoticesButton(notices: notices) { isReadingNotices = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAccount = true
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
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
                                ModelTestLabView()
                            } label: {
                                Label("Model test", systemImage: "camera.viewfinder")
                            }
                            NavigationLink {
                                SlideMovementLabView()
                            } label: {
                                Label("Slide movement lab", systemImage: "move.3d")
                            }
                            NavigationLink {
                                StageControlLabView()
                            } label: {
                                Label("Stage control", systemImage: "dot.radiowaves.left.and.right")
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
            .sheet(isPresented: $isShowingAccount) {
                AccountView()
            }
            .sheet(
                isPresented: $isNaming,
                onDismiss: {
                    // The scan opens after the sheet has gone, so the two never overlap.
                    if startRequested {
                        startRequested = false
                        isScanning = true
                    }
                }
            ) {
                NewTestView(details: $details) {
                    startRequested = true
                    isNaming = false
                }
            }
            // Full screen, so nothing swipes a run away: the scan's own Close (which asks) and
            // End run are the only ways out. The tab bar is covered while scanning.
            .fullScreenCover(
                isPresented: $isScanning,
                onDismiss: {
                    if let name = savedName {
                        savedName = nil
                        finishedSweep = SweepLibrary.sweeps().first { $0.name == name }
                    }
                }
            ) {
                NavigationStack {
                    GuidedScanPage(details: $details) { savedName = $0 }
                }
                .interactiveDismissDisabled(true)
            }
            .sheet(item: $finishedSweep) { sweep in
                NavigationStack {
                    SoilResultScreen(sweep: sweep)
                }
            }
            .task(id: isScanning) { sweeps = SweepLibrary.sweeps() }
        }
    }

    @ViewBuilder
    private var overview: some View {
        if sweeps.isEmpty {
            Text("Tests you take will be summed up here.")
                .foregroundStyle(.secondary)
        } else {
            LabeledContent("Tests", value: sweeps.count.formatted())
            if let latest = sweeps.first {
                LabeledContent("Latest") {
                    VStack(alignment: .trailing) {
                        Text(latest.manifest?.details.sampleID ?? latest.name)
                        Text(latest.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                    }
                }
            }
        }
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
        .environment(FarmStore(fileURL: nil))
        .environment(SupabaseSession(client: nil))
}
