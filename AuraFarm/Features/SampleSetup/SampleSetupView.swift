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
                            } label: {
                                Label("Workbench", systemImage: "hammer")
                            }
                        }
                    #endif
                }
                .safeAreaInset(edge: .bottom) {
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
                    .padding()
                    .background(.bar)
                }
                .navigationDestination(isPresented: $showCamera) {
                    CaptureView(details: $details)
                }
        }
    }
}

#Preview {
    SampleSetupView()
}
