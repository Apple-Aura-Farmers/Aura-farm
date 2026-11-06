import Foundation

/// One soil test, as the field app hands it to the farm manager.
///
/// The field app writes it when a helper sends a sweep on; the farm manager reads it and
/// files it under a farm. It carries what the sweep counted and the sample it came from,
/// never a verdict on the soil: the counts are raw, and only comparable between tests
/// prepared the same way.
///
/// The format is versioned. Add fields as optionals so older reports still decode, and
/// raise `currentSchemaVersion` only for a change an older reader cannot ignore.
public struct SoilReport: Codable, Equatable, Identifiable, Sendable {
    /// The version this build writes, and the newest it can read.
    public static let currentSchemaVersion = 1

    /// The uniform type identifier, declared in both apps' Info.plist.
    public static let typeIdentifier = "io.github.apple-aura-farmers.aurafarm.soil-report"

    /// The file extension the report is saved with.
    public static let fileExtension = "aurafarm"

    public var schemaVersion: Int
    /// Stable for a given sweep, so sending the same sweep twice is recognised as a repeat.
    public var id: UUID
    /// When the report file was written, not when the sample was taken.
    public var createdAt: Date
    public var sample: Sample
    public var capture: Capture
    /// What the detector counted, one entry per organism group it found. Groups it did not
    /// find are left out rather than listed as zero.
    public var organisms: [OrganismCount]
    /// The sweep's frames joined into one picture of the slide, as JPEG, when there is one.
    public var panoramaJPEG: Data?

    public init(
        id: UUID,
        createdAt: Date,
        sample: Sample,
        capture: Capture,
        organisms: [OrganismCount],
        panoramaJPEG: Data? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.sample = sample
        self.capture = capture
        self.organisms = organisms
        self.panoramaJPEG = panoramaJPEG
    }

    /// Every organism counted, across all groups.
    public var totalCount: Int {
        organisms.reduce(0) { $0 + $1.count }
    }

    /// A file name that is safe on every system and says what the report is of, for example
    /// `A12 2026-11-06.aurafarm`.
    public var suggestedFileName: String {
        let safeID = String(
            sample.sampleID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        )
        let day = Self.dayFormatter.string(from: sample.recordedAt)
        return "\(safeID.isEmpty ? "Sample" : safeID) \(day).\(Self.fileExtension)"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension SoilReport {
    /// What the sample is, as the helper entered it before the sweep.
    public struct Sample: Codable, Equatable, Sendable {
        /// Identifier written on the sample bag or tube.
        public var sampleID: String
        /// Which microscope field of view of the sample, counted from 1. Not a farm field.
        public var microscopeField: Int
        /// `flooded` or `drained`. Kept as text so a new value from a newer field app still
        /// reads.
        public var moisture: String
        /// Soil used for the extraction, in grams.
        public var gramsOfSoil: Double?
        /// Extract placed on the slide and scanned, in millilitres.
        public var millilitresScanned: Double?
        /// When the sweep was recorded.
        public var recordedAt: Date

        public init(
            sampleID: String,
            microscopeField: Int,
            moisture: String,
            gramsOfSoil: Double?,
            millilitresScanned: Double?,
            recordedAt: Date
        ) {
            self.sampleID = sampleID
            self.microscopeField = microscopeField
            self.moisture = moisture
            self.gramsOfSoil = gramsOfSoil
            self.millilitresScanned = millilitresScanned
            self.recordedAt = recordedAt
        }
    }

    /// How the counts were made, so a result can be weighed and traced.
    public struct Capture: Codable, Equatable, Sendable {
        /// Frames kept in the sweep.
        public var frameCount: Int
        /// True when the sweep stopped at its size limit instead of finishing its path.
        public var stoppedEarly: Bool
        /// The Core ML model that did the counting, by name.
        public var detectorModel: String
        /// The field app's version, for example `0.1.0 (1)`.
        public var appVersion: String

        public init(frameCount: Int, stoppedEarly: Bool, detectorModel: String, appVersion: String) {
            self.frameCount = frameCount
            self.stoppedEarly = stoppedEarly
            self.detectorModel = detectorModel
            self.appVersion = appVersion
        }
    }

    /// How many of one organism group the sweep counted.
    public struct OrganismCount: Codable, Equatable, Hashable, Sendable {
        /// The detector's class label, for example `Nematoda`.
        public var taxon: String
        public var count: Int

        public init(taxon: String, count: Int) {
            self.taxon = taxon
            self.count = count
        }
    }
}
