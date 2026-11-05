import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks the video a workbench runs on: the ones already pulled into the app, and a button
/// to pull in another from the phone's photo library.
///
/// Debug builds only. It is a form section, so it goes inside a `Form`.
struct DebugVideoPicker: View {
    @Binding var selected: URL?

    @State private var videos: [URL] = []
    @State private var chosen: PhotosPickerItem?
    @State private var isCopying = false
    @State private var problem: String?

    /// Where the workbenches look for videos. Files put here with the Files app or
    /// `xcrun simctl get_app_container` are listed too.
    static var videosDirectory: URL {
        URL.documentsDirectory.appending(path: "DebugVideos", directoryHint: .isDirectory)
    }

    var body: some View {
        Section("Video") {
            PhotosPicker(selection: $chosen, matching: .videos, photoLibrary: .shared()) {
                if isCopying {
                    HStack {
                        ProgressView()
                        Text("Copying it in…")
                    }
                } else {
                    Text("Choose a video…")
                }
            }
            .disabled(isCopying)
            if videos.isEmpty {
                Text("No videos yet.")
                    .foregroundStyle(.secondary)
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
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: findVideos)
        .onChange(of: chosen) { _, item in
            guard let item else { return }
            Task { await copyIn(item) }
        }
    }

    /// Copies the chosen video into `DebugVideos`. A copy rather than a reference, because a
    /// run reads the file for minutes and what the picker hands over does not outlive the
    /// load, and because a video in the library is not a file the app may open directly.
    private func copyIn(_ item: PhotosPickerItem) async {
        problem = nil
        isCopying = true
        defer { isCopying = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                problem = "That video could not be read."
                return
            }
            findVideos()
            selected = movie.url
        } catch {
            problem = error.localizedDescription
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
}

/// A video on its way out of the photo library. The file the system hands over is deleted
/// as soon as the import returns, so it is copied into `DebugVideos` on the way through.
private struct PickedMovie: Transferable {
    var url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let directory = DebugVideoPicker.videosDirectory
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: received.file.lastPathComponent)
            // The same video picked twice should land on the copy already there.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
