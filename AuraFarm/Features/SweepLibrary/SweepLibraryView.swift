import SwiftUI

/// The saved sweeps, newest first. Read only: nothing here edits or deletes a frame.
struct SweepLibraryView: View {
    @State private var sweeps: [SavedSweep] = []

    var body: some View {
        List {
            if sweeps.isEmpty {
                ContentUnavailableView(
                    "No sweeps yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Frames you keep will show up here.")
                )
            } else {
                Section {
                    ForEach(sweeps) { set in
                        NavigationLink {
                            SweepDetailView(sweep: set)
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
        .onAppear { sweeps = SweepLibrary.sweeps() }
    }

    private func row(for set: SavedSweep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title(for: set)).font(.headline)
            Text(detail(for: set)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func title(for set: SavedSweep) -> String {
        guard let details = set.manifest?.details else { return set.name }
        return "\(details.sampleID) · field \(details.field) · \(details.moisture.label)"
    }

    private func detail(for set: SavedSweep) -> String {
        var parts = ["\(set.frameCount) frames"]
        parts.append(set.byteCount.formatted(.byteCount(style: .file)))
        parts.append(set.recordedAt.formatted(date: .abbreviated, time: .shortened))
        if set.panoramaURL == nil, set.frameCount > 1 { parts.append("frames not joined") }
        if set.manifest?.stoppedEarly == true { parts.append("stopped at the size limit") }
        if set.manifest == nil { parts.append("sample details missing") }
        return parts.joined(separator: " · ")
    }

    private var storeLine: String {
        let used = sweeps.reduce(into: Int64(0)) { $0 += $1.byteCount }
        let limit = SweepLibrary.storeByteLimit
        return
            "\(used.formatted(.byteCount(style: .file))) of \(limit.formatted(.byteCount(style: .file))) used."
    }
}

#Preview {
    NavigationStack { SweepLibraryView() }
}
