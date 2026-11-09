import SwiftUI

/// First screen. The sample details are asked for before the camera opens, because every
/// clip needs them, and they then carry from clip to clip until the sample changes.
struct SampleSetupView: View {
    @State private var details = SampleDetails(
        sampleID: "",
        field: 1,
        moisture: .drained,
        gramsOfSoil: SamplePrepView.gramsOfSoil,
        millilitresScanned: nil,
        recordedAt: .now
    )
    @State private var showCamera = false
    @State private var showRecordedSample = false
    /// The sweep the camera just saved, to show its result.
    @State private var finishedSweep: SavedSweep?

    var body: some View {
        NavigationStack {
            SampleDetailsView(details: $details)
                .navigationTitle("Sample details")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SweepLibraryView()
                        } label: {
                            Label("Saved sweeps", systemImage: "square.stack.3d.up")
                        }
                    }
                    #if DEBUG
                        // A workbench for trying the pipeline without a microscope.
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                NavigationLink {
                                    VideoStitchWorkbenchView()
                                } label: {
                                    Label("Stitch from video", systemImage: "film")
                                }
                                NavigationLink {
                                    DetectVideoView()
                                } label: {
                                    Label("Detect from video", systemImage: "viewfinder")
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
                            } label: {
                                Label("Workbench", systemImage: "hammer")
                            }
                        }
                    #endif
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        Button {
                            showCamera = true
                        } label: {
                            Text("Start")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!details.isComplete)

                        // Prototype: the same pipeline, fed from a recorded microscope video.
                        Button {
                            showRecordedSample = true
                        } label: {
                            Label("Use a recorded video", systemImage: "film")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.bar)
                }
                .navigationDestination(isPresented: $showCamera) {
                    CaptureView(details: $details) { name in
                        finishedSweep = SweepLibrary.sweeps().first { $0.name == name }
                    }
                }
                .navigationDestination(isPresented: $showRecordedSample) {
                    RecordedSampleView(details: $details)
                }
                .sheet(item: $finishedSweep) { sweep in
                    NavigationStack {
                        SoilResultScreen(sweep: sweep)
                    }
                }
        }
    }
}

#Preview {
    SampleSetupView()
}
