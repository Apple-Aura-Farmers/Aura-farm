import SwiftUI

/// Runs a recorded video through the capture pipeline so stitching can be tried without a
/// microscope. Debug builds only: it is a workbench, not something a field helper would use.
struct DebugStitchView: View {
    @State private var runner = VideoSweepRunner()
    @State private var startMinutes = 5.0
    @State private var selected: URL?

    var body: some View {
        Form {
            DebugVideoPicker(selected: $selected)

            Section("Start at") {
                // Most of a recording is not a steady pan across a slide, so the part worth
                // trying has to be picked by hand.
                Stepper(
                    "\(Int(startMinutes)) min \(Int((startMinutes - startMinutes.rounded(.down)) * 60)) s",
                    value: $startMinutes, in: 0...90, step: 0.5
                )
                Text("It reads up to \(Int(VideoSweepRunner.maxSecondsRead)) seconds from there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    guard let selected else { return }
                    runner.run(
                        videoURL: selected,
                        startSeconds: startMinutes * 60,
                        details: Self.debugDetails(for: selected)
                    )
                } label: {
                    if runner.isRunning {
                        HStack {
                            ProgressView()
                            Text("Reading the video…")
                        }
                    } else {
                        Text("Run the sweep")
                    }
                }
                .disabled(selected == nil || runner.isRunning)
            } footer: {
                Text("The sweep is saved like any other, so open Saved sweeps to see the result.")
            }

            if let outcome = runner.outcome {
                Section("Result") {
                    Text(outcome)
                    if let name = runner.savedName {
                        LabeledContent("Saved as", value: name)
                    }
                }
            }
        }
        .navigationTitle("Stitch from video")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Marked as debug in the sample ID, so a sweep from a video is never mistaken for one
    /// taken off a microscope.
    private static func debugDetails(for video: URL) -> RecordingMetadata {
        RecordingMetadata(
            sampleID: "DEBUG",
            field: 1,
            moisture: .drained,
            gramsOfSoil: 0,
            millilitresScanned: 0,
            recordedAt: .now
        )
    }
}

#Preview {
    NavigationStack { DebugStitchView() }
}
