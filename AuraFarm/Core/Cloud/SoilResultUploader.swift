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
        /// No row in `soil_samples` has this `sample_code`. The helper typed a code that the
        /// collector never registered, or typed it differently.
        case noSuchSample(code: String)
        /// The result is in the records, but some of its pictures are not.
        case picturesNotSent(missing: Int, of: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "This build is not set up to send tests."
            case .noSuchSample(let code):
                return "No sample is registered as \(code)."
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

    /// Files the report against the sample whose `sample_code` the helper entered.
    ///
    /// Writes with upsert rather than insert, because the report's id is stable for a sweep:
    /// sending the same sweep twice updates its row instead of making a second one, which is
    /// what a helper retrying on a bad connection needs.
    func upload(_ report: SoilReport) async throws {
        let code = report.sample.sampleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sampleID = try await sampleID(forCode: code)
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
        _ report: SoilReport, pictures: [OrganismPicture],
        progress: @MainActor @escaping (Int) -> Void = { _ in }
    ) async throws {
        try await upload(report)
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

    /// The primary key of the sample bearing this code.
    private func sampleID(forCode code: String) async throws -> UUID {
        struct Row: Decodable { var id: UUID }
        let rows: [Row] =
            try await client
            .from("soil_samples")
            .select("id")
            .eq("sample_code", value: code)
            .limit(1)
            .execute()
            .value
        guard let first = rows.first else { throw Failure.noSuchSample(code: code) }
        return first.id
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
