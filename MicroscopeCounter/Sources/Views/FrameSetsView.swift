import SwiftUI

/// The saved sweeps, newest first. Read only: nothing here edits or deletes a frame.
struct FrameSetsView: View {
    @State private var frameSets: [SavedFrameSet] = []

    var body: some View {
        List {
            if frameSets.isEmpty {
                ContentUnavailableView(
                    "No sweeps yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Frames you keep will show up here.")
                )
            } else {
                Section {
                    ForEach(frameSets) { set in
                        NavigationLink {
                            FrameSetViewer(frameSet: set)
                        } label: {
                            row(for: set)
                        }
                    }
                } footer: {
                    Text(storeLine)
                }
            }
        }
        .navigationTitle("Saved sweeps")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { frameSets = FrameSetLibrary.frameSets() }
    }

    private func row(for set: SavedFrameSet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title(for: set)).font(.headline)
            Text(detail(for: set)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func title(for set: SavedFrameSet) -> String {
        guard let details = set.manifest?.details else { return set.name }
        return "\(details.sampleID) · field \(details.field) · \(details.moisture.label)"
    }

    private func detail(for set: SavedFrameSet) -> String {
        var parts = ["\(set.frameCount) frames"]
        parts.append(set.byteCount.formatted(.byteCount(style: .file)))
        parts.append(set.recordedAt.formatted(date: .abbreviated, time: .shortened))
        if set.manifest?.stoppedEarly == true { parts.append("stopped at the size limit") }
        if set.manifest == nil { parts.append("sample details missing") }
        return parts.joined(separator: " · ")
    }

    private var storeLine: String {
        let used = frameSets.reduce(into: Int64(0)) { $0 += $1.byteCount }
        let limit = FrameSetLibrary.storeByteLimit
        return
            "\(used.formatted(.byteCount(style: .file))) of \(limit.formatted(.byteCount(style: .file))) used."
    }
}

/// Swipe through a sweep's frames. Grayscale is applied while drawing, so the file on disk
/// keeps its colour: frames are the raw data for training.
private struct FrameSetViewer: View {
    let frameSet: SavedFrameSet
    /// Grayscale is what the counting work uses, so that is what a frame is checked in.
    @State private var showGrayscale = true
    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            if frameSet.frameURLs.isEmpty {
                ContentUnavailableView(
                    "No frames in this sweep",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The folder is there but holds no frames.")
                )
            } else {
                TabView(selection: $index) {
                    ForEach(Array(frameSet.frameURLs.enumerated()), id: \.element) { position, url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .grayscale(showGrayscale ? 1 : 0)
                        .tag(position)
                    }
                }
                .tabViewStyle(.page)
                .background(Color.black)

                Text("Frame \(index + 1) of \(frameSet.frameCount)")
                    .font(.caption.monospacedDigit())
                    .padding(8)
            }
        }
        .navigationTitle(frameSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("Grayscale", isOn: $showGrayscale).toggleStyle(.button)
            }
        }
    }
}

#Preview {
    NavigationStack { FrameSetsView() }
}
