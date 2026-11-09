import Foundation

/// What a raw clip is of. Saved as a JSON sidecar next to the clip so footage
/// can be traced back to the sample it came from.
struct SampleDetails: Codable, Equatable {
    /// What the field is called: the farmer's name for it, written on the sample bag.
    var sampleID: String
    /// Where the field is. Optional in the type because sweeps saved before it existed are
    /// still read; the form asks for it.
    var location: String?
    /// Why this test is being taken, in the helper's own words. Free text, and nothing reads
    /// it but a person.
    var note: String?
    /// Which microscope field of this sample, counted from 1.
    var field: Int
    var moisture: Moisture
    /// Soil used for the extraction, in grams. Taken from the preparation guide rather
    /// than typed in, because every sample is made the same way.
    var gramsOfSoil: Double?
    /// Extract placed on the slide and scanned, in millilitres. Nothing measures a droplet,
    /// so this stays nil unless something later can put a real figure in it.
    var millilitresScanned: Double?
    var recordedAt: Date

    enum Moisture: String, Codable, CaseIterable, Identifiable {
        case flooded
        case drained

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    /// True when the sweep can be traced back to a place later. Recording is blocked until
    /// then.
    ///
    /// The name and the location are the whole of it: the amounts follow the preparation
    /// guide and are filled in from it, and the note is for whoever reads the result, so
    /// neither can hold a test up.
    var isComplete: Bool {
        !sampleID.trimmingCharacters(in: .whitespaces).isEmpty
            && !(location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Base name for the clip and its sidecar: safe as a file name and sorts by time.
    var fileBaseName: String {
        let safeID = String(
            sampleID
                .trimmingCharacters(in: .whitespaces)
                .map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        )
        let stamp = Self.stampFormatter.string(from: recordedAt)
        return "\(safeID.isEmpty ? "sample" : safeID)_f\(String(format: "%03d", field))_\(stamp)"
    }

    /// UTC so clips from different phones sort together.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
