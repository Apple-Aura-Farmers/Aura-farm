import SwiftUI

/// The scientist's screens: Action, the plots a field helper has asked them to test, and Archive,
/// the tests already done.
struct HomeView: View {
    /// Sends the person back to the role picker. nil where there is no picker, as in previews.
    var onSwitchRole: (() -> Void)?

    init(onSwitchRole: (() -> Void)? = nil) {
        self.onSwitchRole = onSwitchRole
    }

    var body: some View {
        TabView {
            HomeTab(onSwitchRole: onSwitchRole)
                .tabItem { Label("Action", systemImage: "list.bullet.clipboard.fill") }
            ScientistArchiveView()
                .tabItem { Label("Archive", systemImage: "archivebox.fill") }
        }
        .tint(.aura)
    }
}

/// The first tab: the plots waiting for a test. Analyze opens a test already filled in for that
/// plot. The plus button still starts a test from scratch, which the debugging needs.
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

    @Environment(FarmStore.self) private var store

    private var notices: [SweepNotice] { SweepNotice.all(for: sweeps) }

    /// Plots a helper has alerted that have no test newer than the alert, newest alert first.
    private var pending: [(farm: Farm, plot: Plot, asked: Date)] {
        store.farms.flatMap { farm in
            farm.plots.compactMap { plot in
                guard let asked = plot.scientistAlertedAt,
                    asked > (sweeps.latestTest(of: plot, in: farm) ?? .distantPast)
                else { return nil }
                return (farm, plot, asked)
            }
        }
        .sorted { $0.asked > $1.asked }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if pending.isEmpty {
                    ScientistEmptyState(
                        symbol: "pencil.and.list.clipboard", title: "No Action Needed",
                        message: "No samples from the field helpers are needed for analysis right now.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(pending, id: \.plot.id) { item in
                            ScientistRow(
                                corners: item.plot.corners,
                                title: "\(item.farm.farmerName) ∙ \(item.farm.title(of: item.plot))",
                                subtitle: scientistAgo(item.asked), isAlert: true, button: "Analyze"
                            ) {
                                details = .blank
                                details.use(item.plot, of: item.farm)
                                isNaming = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .auraBackground()
            .navigationTitle("Action")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        details = .blank
                        isNaming = true
                    } label: {
                        Label("New Test", systemImage: "plus")
                    }
                }
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
                                SweepLibraryView()
                            } label: {
                                Label("All sweeps", systemImage: "doc.text.image")
                            }
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
