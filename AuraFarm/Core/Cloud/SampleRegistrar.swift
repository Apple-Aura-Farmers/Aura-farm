import Foundation
import Supabase

/// Puts the soil a plot was sampled from into `soil_samples`, and finds it again afterwards.
///
/// Two screens need the same row. The field helper registers the soil when they record what
/// they measured on it, and the microscope operator files a counted test against it later.
/// Whoever gets there first makes the row; the other finds it.
struct SampleRegistrar {
    var client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// nil where Config/Local.xcconfig names no project, which is what an unconfigured
    /// checkout looks like.
    init?(client: SupabaseClient? = Cloud.client) {
        guard let client else { return nil }
        self.client = client
    }

    /// The id of the sample bearing this code, registering it when the records have none.
    ///
    /// nil when there is nothing to register against: a sample belongs to a plot, and a
    /// sweep recorded before plots could be chosen names none. The caller decides what to
    /// say about that, because the two screens say different things.
    ///
    /// Selected before inserting rather than upserted, because the code is the helper's own
    /// label and nothing in the records makes it unique: an upsert would need a conflict
    /// target this table may not have.
    @discardableResult
    func sampleID(
        forCode code: String, plotID: UUID?, place: String?, at collectedAt: Date
    ) async throws -> UUID? {
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

        guard let plotID else { return nil }
        let registered: [Row] =
            try await client
            .from("soil_samples")
            .insert(
                SampleRow(code: code, plotID: plotID, place: place, collectedAt: collectedAt)
            )
            .select("id")
            .execute()
            .value
        return registered.first?.id
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
