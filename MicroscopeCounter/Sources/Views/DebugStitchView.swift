import SwiftUI

/// Runs a recorded video through the capture pipeline so stitching can be tried without a
/// microscope. Debug builds only: it is a workbench, not something a field helper would use.
///
/// Put videos in the app's `Documents/DebugVideos` folder. With the app installed on a
/// simulator that is:
///
///     xcrun simctl get_app_container <device> com.example.microscopecounter data
///
/// then copy the files into `Documents/DebugVideos` inside what it prints. On a phone, the
/// Files app can do it: the app's folder is already visible there.
struct DebugStitchView: View {
    @State private var runner = VideoSweepRunner()
    @State private var videos: [URL] = []
    @State private var startMinutes = 5.0
    @State private var selected: URL?

    /// Where this screen looks for videos to read.
    static var videosDirectory: URL {
        URL.documentsDirectory.appending(path: "DebugVideos", directoryHint: .isDirectory)
    }

    var body: some View {
        Form {
            Section("Video") {
                if videos.isEmpty {
                    ContentUnavailableView(
                        "No videos",
                        systemImage: "film.slash",
                        description: Text("Put .mov or .mp4 files in Documents/DebugVideos.")
                    )
                } else {
                    Picker("File", selection: $selected) {
                        ForEach(videos, id: \.self) { url in
                            Text(url.deletingPathExtension().lastPathComponent)
                                .lineLimit(1)
                                .tag(URL?.some(url))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

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
        .onAppear(perform: findVideos)
        .onChange(of: runner.isRunning) { _, running in
            if !running { findVideos() }
        }
    }

    private func findVideos() {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: Self.videosDirectory, includingPropertiesForKeys: nil)) ?? []
        videos =
            contents
            .filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if selected == nil { selected = videos.first }
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
