import SwiftUI
import UniformTypeIdentifiers

/// Picks the video a workbench runs on: the ones already pulled into the app, and a button
/// to pull in another from anywhere on the phone.
///
/// Debug builds only. It is a form section, so it goes inside a `Form`.
struct DebugVideoPicker: View {
    @Binding var selected: URL?

    @State private var videos: [URL] = []
    @State private var isChoosing = false
    @State private var problem: String?

    /// Where the workbenches look for videos. Files put here with the Files app or
    /// `xcrun simctl get_app_container` are listed too.
    static var videosDirectory: URL {
        URL.documentsDirectory.appending(path: "DebugVideos", directoryHint: .isDirectory)
    }

    var body: some View {
        Section("Video") {
            Button("Choose a video…") { isChoosing = true }
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
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.movie]) { result in
            copyIn(result)
        }
    }

    /// Copies the chosen file into `DebugVideos`. A copy rather than a reference, because a
    /// run reads the file for minutes and the permission to read it where it sits does not
    /// last that long.
    private func copyIn(_ result: Result<URL, Error>) {
        problem = nil
        do {
            let picked = try result.get()
            let scoped = picked.startAccessingSecurityScopedResource()
            defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
            try FileManager.default.createDirectory(
                at: Self.videosDirectory, withIntermediateDirectories: true)
            let destination = Self.videosDirectory.appending(path: picked.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: picked, to: destination)
            }
            findVideos()
            selected = destination
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
