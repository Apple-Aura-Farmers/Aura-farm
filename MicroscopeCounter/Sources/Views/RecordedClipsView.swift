import AVKit
import CoreImage
import SwiftUI

/// The clips saved on this phone, newest first. Read only: clips are the source for
/// training data, so nothing here edits or deletes them.
struct RecordedClipsView: View {
    @State private var clips: [SavedClip] = []

    var body: some View {
        List(clips) { clip in
            NavigationLink {
                ClipPlayer(clip: clip)
            } label: {
                row(for: clip)
            }
        }
        .navigationTitle("Recorded clips")
        .overlay {
            if clips.isEmpty {
                ContentUnavailableView(
                    "No clips yet",
                    systemImage: "film",
                    description: Text("Clips you record are kept on this phone.")
                )
            }
        }
        .onAppear { clips = ClipLibrary.clips() }
    }

    private func row(for clip: SavedClip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(for: clip)).font(.headline)
            Text(detail(for: clip))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func title(for clip: SavedClip) -> String {
        guard let metadata = clip.metadata else { return clip.name }
        return "\(metadata.sampleID) · field \(metadata.field)"
    }

    private func detail(for clip: SavedClip) -> String {
        var parts = [clip.recordedAt.formatted(date: .abbreviated, time: .shortened)]
        if let metadata = clip.metadata {
            parts.append(metadata.moisture.label)
            if let grams = metadata.gramsOfSoil { parts.append("\(grams.formatted(.number)) g") }
            if let millilitres = metadata.millilitresScanned {
                parts.append("\(millilitres.formatted(.number)) mL")
            }
        } else {
            parts.append("No sample details")
        }
        parts.append(clip.byteCount.formatted(.byteCount(style: .file)))
        return parts.joined(separator: " · ")
    }
}

private struct ClipPlayer: View {
    let clip: SavedClip
    @State private var player = AVPlayer()
    /// Grayscale is what the counting pipeline works on, so it is what the clip is checked in.
    @State private var showGrayscale = true

    var body: some View {
        VideoPlayer(player: player)
            .navigationTitle(clip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Grayscale", isOn: $showGrayscale)
                        .toggleStyle(.button)
                }
            }
            .onAppear { load() }
            .onChange(of: showGrayscale) { _, _ in load() }
            .onDisappear { player.pause() }
    }

    /// Grayscale is applied while playing. The clip on disk stays in colour: it is the
    /// source for training data, and the pipeline's grayscale step works on copies.
    private func load() {
        let item = AVPlayerItem(url: clip.url)
        if showGrayscale {
            item.videoComposition = AVMutableVideoComposition(
                asset: item.asset,
                applyingCIFiltersWithHandler: { request in
                    request.finish(
                        with: request.sourceImage.applyingFilter("CIPhotoEffectMono"), context: nil)
                }
            )
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }
}

#Preview {
    NavigationStack { RecordedClipsView() }
}
