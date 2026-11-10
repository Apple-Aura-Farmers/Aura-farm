import Foundation
import Observation

/// The farms this phone's field helper looks after, saved as one JSON file in the app's own
/// storage. Nothing leaves the phone yet.
@Observable
final class FarmStore {
    private(set) var farms: [Farm] = []
    /// Set when the saved farms could not be read or written, so the screen can say so
    /// instead of quietly showing an empty list.
    private(set) var problem: String?

    @ObservationIgnored private let fileURL: URL?

    /// - Parameter fileURL: where the farms are kept. nil keeps them in memory only, for
    ///   previews and tests.
    init(fileURL: URL? = FarmStore.defaultFileURL, farms: [Farm] = []) {
        self.fileURL = fileURL
        self.farms = farms
        if fileURL != nil { load() }
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Farms.json")
    }

    func add(_ farm: Farm) {
        farms.append(farm)
        save()
    }

    /// Replaces the saved farm that has the same id. Does nothing if it is not there.
    func update(_ farm: Farm) {
        guard let index = farms.firstIndex(where: { $0.id == farm.id }) else { return }
        farms[index] = farm
        save()
    }

    func delete(_ farm: Farm) {
        farms.removeAll { $0.id == farm.id }
        save()
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            farms = try decoder.decode([Farm].self, from: Data(contentsOf: fileURL))
        } catch {
            // Keep the unreadable file rather than letting the next save write over it.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.deletingLastPathComponent()
                .appending(path: "Farms-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            problem =
                "The saved farms could not be read. The old file was kept aside and the list "
                + "started empty."
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(farms).write(to: fileURL, options: .atomic)
        } catch {
            problem = "The farms could not be saved: \(error.localizedDescription)"
        }
    }
}
