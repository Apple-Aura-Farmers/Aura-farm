import SwiftUI

/// Runs the detector over a recorded video and shows a picture of everything it found.
///
/// Debug builds only, and nothing to do with a sweep: this is here to judge the model. Every
/// organism is given an id the first time it is seen and followed from frame to frame, so
/// the count is of organisms rather than of detections, and a picture is kept each time
/// something new turns up.
struct DetectVideoView: View {
    @State private var runner = VideoDetectionRunner()
    @State private var startMinutes = 0.0
    @State private var selected: URL?
    @State private var showing: Picture?

    /// A picture the sheet is showing. A wrapper because a URL is not identifiable.
    private struct Picture: Identifiable {
        var url: URL
        var id: String { url.absoluteString }
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        Form {
            DebugVideoPicker(selected: $selected)

            Section("Start at") {
                Stepper(
                    "\(Int(startMinutes)) min \(Int((startMinutes - startMinutes.rounded(.down)) * 60)) s",
                    value: $startMinutes, in: 0...90, step: 0.5
                )
                Text(
                    "It reads up to \(Int(VideoDetectionRunner.maxSecondsRead)) seconds from there."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    guard let selected else { return }
                    runner.run(videoURL: selected, startSeconds: startMinutes * 60)
                } label: {
                    if runner.isRunning {
                        HStack {
                            ProgressView()
                            Text("Watching the video…")
                        }
                    } else {
                        Text("Find everything in it")
                    }
                }
                .disabled(selected == nil || runner.isRunning)
            } footer: {
                Text(
                    """
                    Every third frame goes through the model. A picture is kept whenever \
                    something new appears, with its box drawn on, and lands in Detections in \
                    the Files app.
                    """
                )
            }

            if let outcome = runner.outcome {
                Section("Result") {
                    Text(outcome)
                    if runner.total > 0 {
                        LabeledContent("Found", value: "\(runner.total)")
                        ForEach(runner.countByLabel.sorted { $0.key < $1.key }, id: \.key) { entry in
                            LabeledContent(entry.key, value: "\(entry.value)")
                        }
                    }
                }
            }

            if !runner.savedFrames.isEmpty {
                Section("Pictures") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(runner.savedFrames, id: \.self) { url in
                            Button {
                                showing = Picture(url: url)
                            } label: {
                                thumbnail(url)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Detect from video")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { picture in
            NavigationStack {
                // A scroll view proposes no size, so the picture came up at its full pixel
                // size and had to be scrolled across. Let it fit the sheet instead.
                self.picture(picture.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(picture.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: URL) -> some View {
        picture(url)
            .frame(height: 90)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func picture(_ url: URL) -> some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Color.secondary.opacity(0.2)
        }
    }
}

#Preview {
    NavigationStack { DetectVideoView() }
}
