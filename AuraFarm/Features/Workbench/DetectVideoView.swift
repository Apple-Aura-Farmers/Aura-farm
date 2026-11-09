import PhotosUI
import SwiftUI

/// Runs the detector over a recorded video, or over a single photograph, and shows a picture
/// of everything it found.
///
/// Debug builds only, and nothing to do with a sweep: this is here to judge the model. Over
/// a video, every organism is given an id the first time it is seen and followed from frame
/// to frame, so the count is of organisms rather than of detections, and a picture is kept
/// each time something new turns up. A photograph is one look at a slide, so every box in it
/// is its own find.
struct DetectVideoView: View {
    @State private var runner = VideoDetectionRunner()
    @State private var startMinutes = 0.0
    @State private var selected: URL?
    @State private var chosenPhoto: PhotosPickerItem?
    @State private var photoProblem: String?
    @State private var showing: Picture?
    /// How far the open picture is zoomed in, as a multiple of fitting the screen.
    @State private var zoom = 1.0
    @GestureState private var pinch = 1.0

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

            Section {
                PhotosPicker(selection: $chosenPhoto, matching: .images, photoLibrary: .shared()) {
                    Text("Or run it on one photo…")
                }
                .disabled(runner.isRunning)
                if let photoProblem {
                    Text(photoProblem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(
                    """
                    A microscope still rather than footage. The whole picture goes through                     the model once and comes back with its boxes drawn on.
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
        .navigationTitle("Detect in a sample")
        .onChange(of: chosenPhoto) { _, item in
            guard let item else { return }
            Task {
                photoProblem = nil
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        photoProblem = "That photo could not be read."
                        return
                    }
                    runner.run(photo: data, named: "photo")
                } catch {
                    photoProblem = error.localizedDescription
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { picture in
            NavigationStack {
                zoomablePicture(picture.url)
                    .navigationTitle(picture.url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = nil }
                        }
                    }
            }
            // Every picture opens fitting the screen, however the one before was left.
            .onAppear { zoom = 1 }
        }
    }

    /// The picture fitted to the sheet, which it is opened at, and zoomable from there: the
    /// boxes are small enough on a 1920 wide frame that a fitted picture cannot settle
    /// whether the model found an organism or a speck of grit.
    @ViewBuilder
    private func zoomablePicture(_ url: URL) -> some View {
        if let image = UIImage(contentsOfFile: url.path) {
            GeometryReader { proxy in
                // Sized from the picture's own shape rather than the sheet's, or zooming in
                // would scroll into the empty bands above and below a letterboxed frame.
                let fitted = Self.sizeFitting(image.size, in: proxy.size)
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fitted.width * zoomedBy, height: fitted.height * zoomedBy)
                        // Centred while it is smaller than the sheet.
                        .frame(
                            maxWidth: max(proxy.size.width, fitted.width * zoomedBy),
                            maxHeight: max(proxy.size.height, fitted.height * zoomedBy)
                        )
                }
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
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    private var zoomedBy: Double { clamped(zoom * pinch) }

    /// Fitting the screen at the bottom; past eight times a 1920 wide frame is pixels.
    private func clamped(_ value: Double) -> Double { min(max(value, 1), 8) }

    /// The largest size with `size`'s shape that fits inside `bounds`.
    static func sizeFitting(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
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
