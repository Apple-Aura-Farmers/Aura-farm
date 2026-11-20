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

    /// The send to the records that is still in flight, if there is one. Each new send waits
    /// for it before starting, so two changes made close together reach the records in the
    /// order they were made rather than the order the network happens to finish in. Held here
    /// rather than beside `publish` because an extension cannot carry state.
    @ObservationIgnored var publishing: Task<Void, Never>?

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

    /// Takes in what the records hold.
    ///
    /// A farm in both is replaced by the records' copy, which is the one every other phone
    /// can see. A farm only this phone has is kept or dropped on whether the records have
    /// ever handed it back: never, and it is one nobody has published yet; before but not
    /// now, and it is one somebody has deleted.
    func merge(_ records: [Farm]) {
        var byID: [UUID: Farm] = [:]
        // A farm the records have never handed back is one nobody has published yet, so it
        // stays on the phone. One they handed back before and no longer mention is one
        // somebody has deleted, so it goes rather than sitting here as land that no other
        // phone can see. Only a pull that worked gets this far, so a lost connection takes
        // nothing away.
        for farm in farms where farm.publishedAt == nil { byID[farm.id] = farm }
        for farm in records {
            var farm = farm
            farm.publishedAt = Date()
            byID[farm.id] = farm
        }
        farms = byID.values.sorted { $0.createdAt < $1.createdAt }
        save()
    }

    /// Says what went wrong somewhere else, so the one banner on the map can show it.
    func report(_ problem: String?) {
        self.problem = problem
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
            problem = String(
                localized: "The saved farms could not be read. The old file was kept aside and the list started empty."
            )
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
            problem = String(localized: "The farms could not be saved: \(error.localizedDescription)")
        }
    }
}
