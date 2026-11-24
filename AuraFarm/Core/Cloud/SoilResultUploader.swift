import AuraFarmKit
import Foundation
import Supabase

/// Sends a finished sweep to the `soil_results` table.
///
/// The sweep is already saved on the phone before this runs, so a failure here costs the
/// sending and not the test. The helper can be out of signal all morning and send later.
struct SoilResultUploader {
    var client: SupabaseClient

    enum Failure: LocalizedError {
        /// Config/Local.xcconfig names no project, so this build has no backend.
        case notConfigured
        /// No row in `soil_samples` has this `sample_code`, and the sweep names no plot to
        /// register one against: it was recorded before plots could be chosen.
        case noSuchSample(code: String)
        /// The operator's own sample: it has no farm to be filed under.
        case ownSample
        /// The result is in the records, but some of its pictures are not.
        case picturesNotSent(missing: Int, of: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "This build is not set up to send tests."
            case .ownSample:
                return "This is your own sample. Only tests of a farm can be uploaded."
            case .noSuchSample(let code):
                return """
                    No sample is registered as \(code), and this test names no plot, \
                    so one cannot be registered for it. Run the test again from a farm plot.
                    """
            case .picturesNotSent(let missing, let total, let reason):
                return
                    "The result was sent, but \(missing) of its \(total) pictures were not. "
                    + "Try again to send them. (\(reason))"
            }
        }
    }

    init?(client: SupabaseClient? = Cloud.client) {
        guard let client else { return nil }
        self.client = client
    }

    /// Files the report against the sample whose `sample_code` the helper entered, registering
    /// that sample on the first test sent for it.
    ///
    /// `details` is what the helper filled in before the sweep; the plot and location it
    /// carries are what a new `soil_samples` row needs, and the report itself does not carry
    /// them. Without it only an already registered sample can be filed against.
    ///
    /// Writes with upsert rather than insert, because the report's id is stable for a sweep:
    /// sending the same sweep twice updates its row instead of making a second one, which is
    /// what a helper retrying on a bad connection needs.
    func upload(_ report: SoilReport, from details: SampleDetails? = nil) async throws {
        // Never matched by its name alone: that could be a farm's sample with the same name.
        if details?.isOwnSample == true { throw Failure.ownSample }
        let code = report.sample.sampleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sampleID = try await sampleID(forCode: code, from: details, at: report.sample.recordedAt)
        try await client
            .from("soil_results")
            .upsert(ResultRow(report: report, sampleID: sampleID))
            .execute()
        try await replaceCounts(of: report)
    }

    /// The private storage the organism pictures go in. Made by supabase/organism-images.sql.
    static let pictureBucket = "organism-images"
    /// How many pictures are sent at once.
    static let picturesAtOnce = 4

    /// Files the report, then sends its pictures. The result goes first, so a picture that fails
    /// costs the picture and not the count; sending again replaces what is already there.
    /// - Parameter progress: how many pictures are sent so far, on the main actor.
    func upload(
        _ report: SoilReport, pictures: [OrganismPicture], from details: SampleDetails? = nil,
        progress: @MainActor @escaping (Int) -> Void = { _ in }
    ) async throws {
        try await upload(report, from: details)
        let bucket = client.storage.from(Self.pictureBucket)
        try await Self.send(pictures, progress: progress) { picture in
            try await bucket.upload(
                picture.image.path, data: Data(contentsOf: picture.file),
                options: FileOptions(contentType: "image/jpeg", upsert: true))
        }
    }

    /// Sends every picture, a few at a time. One that fails does not stop the others; when any
    /// failed, says how many and why the first one did.
    static func send(
        _ pictures: [OrganismPicture], atOnce: Int = picturesAtOnce,
        progress: @MainActor @escaping (Int) -> Void = { _ in },
        with sendOne: @escaping @Sendable (OrganismPicture) async throws -> Void
    ) async throws {
        var waiting = pictures[...]
        var sent = 0
        var problems: [String] = []
        await withTaskGroup(of: String?.self) { group in
            func next() {
                guard let picture = waiting.popFirst() else { return }
                group.addTask {
                    do {
                        try await sendOne(picture)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            for _ in 0..<max(atOnce, 1) { next() }
            while let result = await group.next() {
                if let problem = result { problems.append(problem) } else { sent += 1 }
                await progress(sent)
                next()
            }
        }
        if let reason = problems.first {
            throw Failure.picturesNotSent(
                missing: problems.count, of: pictures.count, reason: reason)
        }
    }

    /// Rewrites this result's rows in `microorganisms`.
    ///
    /// Deletes before inserting rather than upserting, so a group that a re-sent sweep no
    /// longer counts does not linger from the send before it. Every count is in
    /// `soil_results.report` as well, so a failure between the two loses nothing that
    /// sending again does not put back.
    private func replaceCounts(of report: SoilReport) async throws {
        try await client
            .from("microorganisms")
            .delete()
            .eq("result_id", value: report.id.uuidString)
            .execute()
        let rows = MicroorganismRow.rows(for: report)
        guard !rows.isEmpty else { return }
        try await client.from("microorganisms").insert(rows).execute()
    }

    /// The primary key of the sample bearing this code, registering the sample if the records
    /// do not have it yet.
    ///
    /// Nothing else in the app writes `soil_samples`, so without this a test could only ever
    /// be sent for a sample somebody had registered by hand in the dashboard.
    ///
    /// Selected before inserting rather than upserted, because the code is the helper's own
    /// label and nothing in the records makes it unique: an upsert would need a conflict
    /// target this table may not have.
    private func sampleID(
        forCode code: String,
        from details: SampleDetails?,
        at recordedAt: Date
    ) async throws -> UUID {
        struct Row: Decodable { var id: UUID }
        let rows: [Row] =
            try await client
            .from("soil_samples")
            .select("id")
            .eq("sample_code", value: code)
            .limit(1)
            .execute()
            .value
        if let first = rows.first { return first.id }

        guard let plotID = details?.plotID else { throw Failure.noSuchSample(code: code) }
        let registered: [Row] =
            try await client
            .from("soil_samples")
            .insert(
                SampleRow(
                    code: code, plotID: plotID, place: details?.location,
                    collectedAt: recordedAt)
            )
            .select("id")
            .execute()
            .value
        guard let first = registered.first else { throw Failure.noSuchSample(code: code) }
        return first.id
    }
}

/// One row of `soil_samples`: the soil the microscope tests are of.
///
/// `collected_by` is not sent. The column defaults to whoever is signed in, which is the
/// helper registering the sample.
struct SampleRow: Encodable {
    var id = UUID()
    var code: String
    var plotID: UUID
    /// The plot's middle as well-known text. `location` is a PostGIS column, so the line of
    /// text a sample shows the helper is not something it accepts: it parses geometry, and
    /// anything else comes back as "parse error, invalid geometry".
    var location: String?
    var collectedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code = "sample_code"
        case plotID = "plot_id"
        case location
        case collectedAt = "collected_at"
    }

    /// `place` is what `Plot.locationDescription` wrote. A plot whose middle cannot be read
    /// back out of it sends no location: the plot it is filed under carries the land anyway.
    init(id: UUID = UUID(), code: String, plotID: UUID, place: String?, collectedAt: Date) {
        self.id = id
        self.code = code
        self.plotID = plotID
        self.location =
            place
            .flatMap(GeoPoint.init(locationDescription:))
            .map(PlotBoundary.wellKnownText(for:))
        self.collectedAt = collectedAt
    }
}

/// One row of `soil_results`.
///
/// The columns that the farm manager sorts and filters on are their own fields; everything
/// else in the report rides along in the `report` json, so a field added to the report needs
/// no migration here.
struct ResultRow: Encodable {
    var id: UUID
    var sampleID: UUID
    var gramsOfSoil: Double?
    var millilitresScanned: Double?
    var millilitresOfWater: Double?
    var frameCount: Int
    var detectorModel: String
    var recordedAt: Date
    /// The report without its panorama. The picture is megabytes of JPEG and belongs in
    /// storage with a row in `result_media`, not base64 inside a json column.
    var report: SoilReport

    enum CodingKeys: String, CodingKey {
        case id
        case sampleID = "sample_id"
        case gramsOfSoil = "grams_of_soil"
        case millilitresScanned = "millilitres_scanned"
        case millilitresOfWater = "millilitres_of_water"
        case frameCount = "frame_count"
        case detectorModel = "detector_model"
        case recordedAt = "recorded_at"
        case report
    }

    init(report: SoilReport, sampleID: UUID) {
        var stripped = report
        stripped.panoramaJPEG = nil

        self.id = report.id
        self.sampleID = sampleID
        self.gramsOfSoil = report.sample.gramsOfSoil
        self.millilitresScanned = report.sample.millilitresScanned
        self.millilitresOfWater = report.sample.millilitresOfWater
        self.frameCount = report.capture.frameCount
        self.detectorModel = report.capture.detectorModel
        self.recordedAt = report.sample.recordedAt
        self.report = stripped
    }
}

/// One row of `microorganisms`, the table the farm manager counts from without reading json.
struct MicroorganismRow: Encodable, Equatable {
    var resultID: UUID
    /// A label the `microorganisms.type` enum accepts, never the detector's raw label.
    var type: String
    var count: Int

    enum CodingKeys: String, CodingKey {
        case resultID = "result_id"
        case type
        case count
    }

    /// What each detector label is called in the `microorganisms.type` enum.
    ///
    /// `Nematoda` is the spelling the weights before the current ones used, and it means the
    /// same animal as `Nematode`, so it is folded in rather than dropped.
    ///
    /// `Monogononta` and `Hypotrichida` are groups the app can name but the enum has no value
    /// for, so a report carrying one is left out of this table. Postgres rejects the whole
    /// statement for one unknown label, and a count the manager cannot filter on beats an
    /// upload that fails.
    static let storedTaxa = [
        "Arcellinida": "Arcellinida",
        "Digononta": "Digononta",
        "Euglenoid": "Euglenoid",
        "Nematoda": "Nematode",
        "Nematode": "Nematode",
        "Volvox": "Volvox",
    ]

    /// The rows to write for a report, one per enum value it has a count for.
    ///
    /// Counts that fold onto the same enum value are added together, because the table's key
    /// is the result and the type, so two rows of the same type would collide.
    static func rows(for report: SoilReport) -> [MicroorganismRow] {
        var counts: [String: Int] = [:]
        for organism in report.organisms {
            guard let stored = storedTaxa[organism.taxon] else { continue }
            counts[stored, default: 0] += organism.count
        }
        return
            counts
            .sorted { $0.key < $1.key }
            .map { MicroorganismRow(resultID: report.id, type: $0.key, count: $0.value) }
    }
}
