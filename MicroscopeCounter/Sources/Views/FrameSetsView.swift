import SwiftUI
import UIKit

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
        if set.panoramaURL == nil, set.frameCount > 1 { parts.append("frames not joined") }
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

/// Plays a sweep back like a clip, and lets the helper step through it frame by frame.
/// Grayscale is applied while drawing, so the files on disk keep their colour: frames are
/// the raw data the counting work will be trained on.
private struct FrameSetViewer: View {
    let frameSet: SavedFrameSet

    /// One second a frame. These are separate fields of view, not continuous motion, so
    /// playback is a slideshow: fast enough to watch, slow enough to see what is in a frame.
    private static let secondsPerFrame = 1.0

    private enum Mode: String, CaseIterable, Identifiable {
        case panorama = "Panorama"
        case grid = "Grid"
        case frames = "Frames"
        var id: String { rawValue }
    }

    /// Grayscale is what the counting work uses, so that is what a sweep is checked in.
    @State private var showGrayscale = true
    @State private var mode = Mode.panorama
    @State private var index = 0
    @State private var isPlaying = false
    /// How far the joined picture is zoomed in, as a multiple of fitting the screen.
    @State private var zoom = 1.0
    @GestureState private var pinch = 1.0
    /// Decoded once, so playback does not stall on reading each frame off disk.
    @State private var frames: [UIImage] = []
    /// The frames the stitcher could not place, by index, once it has been asked.
    @State private var unplaced: Set<Int>?

    var body: some View {
        VStack(spacing: 0) {
            if frameSet.frameURLs.isEmpty {
                ContentUnavailableView(
                    "No frames in this sweep",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The folder is there but holds no frames.")
                )
            } else if frames.isEmpty {
                ProgressView("Loading frames")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("View", selection: $mode) {
                    ForEach(modes) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch mode {
                case .panorama:
                    if let url = frameSet.panoramaURL { panorama(at: url) }
                case .grid:
                    grid
                case .frames:
                    player
                    controls
                }
            }
        }
        .navigationTitle(frameSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("Grayscale", isOn: $showGrayscale).toggleStyle(.button)
            }
        }
        .task {
            // A sweep that never joined has no panorama to open on.
            if frameSet.panoramaURL == nil { mode = .grid }
            await loadFrames()
        }
        .task(id: mode) { await checkPlacementIfNeeded() }
        .task(id: isPlaying) { await playIfNeeded() }
        .onChange(of: mode) { _, new in
            if new == .panorama { isPlaying = false }
        }
    }

    /// Panorama is only worth offering once there is one; a sweep that failed to join
    /// opens on the grid, which is where the reason usually shows.
    private var modes: [Mode] {
        frameSet.panoramaURL == nil ? [.grid, .frames] : Mode.allCases
    }

    /// The frames laid out the way the slide was walked, so neighbours on screen are
    /// neighbours on the slide. Whether the sweep joins up is easiest to judge here: a
    /// frame that does not continue into the one beside it is one the stitcher cannot
    /// place either.
    private var grid: some View {
        let layout = SweepLayout(frameCount: frames.count)
        return ScrollView {
            VStack(spacing: 2) {
                ForEach(0..<layout.rows, id: \.self) { row in
                    let indices = layout.indices(inRow: row, frameCount: frames.count)
                    HStack(spacing: 2) {
                        ForEach(indices, id: \.self) { index in
                            cell(at: index)
                        }
                        // A sweep that stopped early leaves a part row. Holding the empty
                        // places open keeps the frames at the size the full rows are.
                        ForEach(0..<(layout.columns - indices.count), id: \.self) { _ in
                            Color.clear.aspectRatio(frameAspect, contentMode: .fit)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)

            Text(placementLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    /// Every cell is the shape of a frame, so a part row does not stretch what is in it.
    private var frameAspect: Double {
        guard let first = frames.first, first.size.height > 0 else { return 4.0 / 3.0 }
        return first.size.width / first.size.height
    }

    private func cell(at index: Int) -> some View {
        Image(uiImage: frames[index])
            .resizable()
            .aspectRatio(frameAspect, contentMode: .fit)
            .grayscale(showGrayscale ? 1 : 0)
            .overlay(alignment: .topLeading) {
                Text("\(index)")
                    .font(.caption2.monospacedDigit().bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .padding(3)
            }
            .overlay {
                if unplaced?.contains(index) == true {
                    Rectangle().strokeBorder(.red, lineWidth: 2)
                }
            }
            .accessibilityLabel(
                unplaced?.contains(index) == true
                    ? "Frame \(index), which could not be joined" : "Frame \(index)")
    }

    private var placementLine: String {
        guard let unplaced else { return "Checking which frames line up…" }
        if unplaced.isEmpty {
            return "Every frame lined up with the one before it."
        }
        let list = unplaced.sorted().map(String.init).joined(separator: ", ")
        return
            "Outlined in red: \(unplaced.count) frame\(unplaced.count == 1 ? "" : "s") the "
            + "stitcher could not place (\(list)). A frame that shares too little with the "
            + "one before it cannot be lined up."
    }

    /// Asks the stitcher where it would put each frame. It registers every pair, so it is
    /// done once, off the main thread, and only when the grid is actually looked at.
    private func checkPlacementIfNeeded() async {
        guard mode == .grid, unplaced == nil, frameSet.frameURLs.count >= 2 else { return }
        let urls = frameSet.frameURLs
        let missing = await Task.detached(priority: .userInitiated) { () -> Set<Int> in
            guard let offsets = try? PanoramaStitcher.offsets(for: urls) else {
                return Set(0..<urls.count)
            }
            return Set(offsets.enumerated().filter { $0.element == nil }.map(\.offset))
        }.value
        unplaced = missing
    }

    /// The frames joined into one picture of the slide. It takes its shape from wherever the
    /// sample was moved, so it is rarely a neat rectangle and scrolls both ways.
    private func panorama(at url: URL) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: proxy.size.height * zoomedBy)
                            .grayscale(showGrayscale ? 1 : 0)
                    } placeholder: {
                        ProgressView().frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                // Where the sweep started is where it opens.
                .defaultScrollAnchor(.topLeading)
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = clamped(zoom * value.magnification) }
                )
                .onTapGesture(count: 2) {
                    withAnimation { zoom = zoom > 1 ? 1 : 3 }
                }
            }
            .background(Color.black)

            VStack(spacing: 4) {
                Text(
                    "Joined from the \(frameSet.frameCount) frames of this sweep, as far as "
                        + "they lined up — Grid shows which did not. Pinch to zoom, drag to "
                        + "move around. Black is slide the sweep never covered."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                if let manifest = frameSet.manifest {
                    Text(summary(of: manifest))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 10)
        }
    }

    /// Swipe to step through, or let playback advance it.
    private var player: some View {
        TabView(selection: $index) {
            ForEach(Array(frames.enumerated()), id: \.offset) { position, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .tag(position)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .grayscale(showGrayscale ? 1 : 0)
        .background(Color.black)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                Button {
                    isPlaying = false
                    index = max(index - 1, 0)
                } label: {
                    Image(systemName: "backward.frame.fill").font(.title2)
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous frame")

                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button {
                    isPlaying = false
                    index = min(index + 1, frames.count - 1)
                } label: {
                    Image(systemName: "forward.frame.fill").font(.title2)
                }
                .disabled(index == frames.count - 1)
                .accessibilityLabel("Next frame")
            }

            Text("Frame \(index + 1) of \(frames.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if let manifest = frameSet.manifest {
                Text(summary(of: manifest))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 10)
    }

    private var zoomedBy: Double { clamped(zoom * pinch) }

    /// Never smaller than fitting the screen, and only so far in before the frames turn to mush.
    private func clamped(_ value: Double) -> Double { min(max(value, 1), 8) }

    private func summary(of manifest: FrameSetManifest) -> String {
        var line =
            "\(manifest.details.sampleID) · field \(manifest.details.field) · \(manifest.details.moisture.label)"
        line += " · \(frameSet.byteCount.formatted(.byteCount(style: .file)))"
        if manifest.stoppedEarly { line += " · stopped at the size limit" }
        return line
    }

    /// Reading and decoding happens off the main thread; only the array is handed back to it.
    private func loadFrames() async {
        guard frames.isEmpty else { return }
        let urls = frameSet.frameURLs
        let decoded = await Task.detached(priority: .userInitiated) {
            urls.compactMap { UIImage(contentsOfFile: $0.path) }
        }.value
        frames = decoded
    }

    private func playIfNeeded() async {
        guard isPlaying, frames.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.secondsPerFrame))
            guard !Task.isCancelled else { return }
            index = (index + 1) % frames.count
        }
    }
}

#Preview {
    NavigationStack { FrameSetsView() }
}
