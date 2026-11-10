import Foundation
import os

/// Reads and writes one JSON file inside a sweep folder, with the settings both advice stores
/// share.
enum SweepJSONFile {
    /// nil when the file is missing or can't be read; the reason is logged in debug builds.
    static func read<T: Decodable>(_ type: T.Type, named name: String, in sweep: SavedSweep, what: String) -> T? {
        guard let data = try? Data(contentsOf: sweep.url.appending(path: name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            #if DEBUG
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")
                    .debug("\(what) could not be read: \(String(describing: error), privacy: .public)")
            #endif
            return nil
        }
    }

    static func write<T: Encodable>(_ value: T, named name: String, in sweep: SavedSweep) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: sweep.url.appending(path: name), options: .atomic)
    }
}
