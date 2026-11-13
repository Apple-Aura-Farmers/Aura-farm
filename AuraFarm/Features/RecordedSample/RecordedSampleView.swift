import SwiftUI

/// Runs a recorded microscope video as if the camera were seeing it: the quality check, the
/// guided sweep, the detector and the tally all run as they do live, and the result is an
/// ordinary saved sweep with its counts.
///
/// A prototype path, for seeing the whole flow without a microscope to hand.
struct RecordedSampleView: View {
    @Binding var details: SampleDetails

    @State private var runner = VideoSweepRunner()
    @State private var selected: URL?
    @State private var startSeconds = 0.0
    /// The sweep the last run saved, once it is ready to show.
    @State private var result: SavedSweep?

    var body: some View {
        Form {
            Section {
                Text(
                    "Choose a video recorded through the microscope. It runs exactly as a live "
                        + "sweep would: the image is checked, frames are kept along the sweep path, "
                        + "and every organism the model finds is counted once."
                )
                .font(.callout)
            }

            Section("Sample") {
                // Chosen on the New Test screen, so the recording is filed under that farm.
                LabeledContent("Farm", value: details.sampleID)
            }

            DebugVideoPicker(selected: $selected)

            Section {
                Stepper(value: $startSeconds, in: 0...3_600, step: 5) {
                    LabeledContent("Start at", value: startLabel)
                }
            } footer: {
                Text("Skip to where the slide starts moving steadily across the view.")
            }

            Section {
                Button(action: run) {
                    if runner.isRunning {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Running the sample…")
                        }
                    } else {
                        Text("Run sample")
                            .font(.headline)
                    }
                }
                .disabled(selected == nil || !details.isComplete || runner.isRunning)
            } footer: {
                if let outcome = runner.outcome {
                    Text(outcome)
                } else if !details.isComplete {
                    Text("Choose a farm first.")
                }
            }
        }
        .navigationTitle("Recorded sample")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: runner.savedName) { _, name in
            guard let name else { return }
            result = SweepLibrary.sweeps().first { $0.name == name }
        }
        .sheet(item: $result) { sweep in
            NavigationStack {
                SoilResultScreen(sweep: sweep)
            }
        }
    }

    /// "1:05": minutes and seconds into the video.
    private var startLabel: String {
        Duration.seconds(startSeconds).formatted(.time(pattern: .minuteSecond))
    }

    private func run() {
        guard let selected else { return }
        details.recordedAt = .now
        runner.run(videoURL: selected, startSeconds: startSeconds, details: details)
    }
}
