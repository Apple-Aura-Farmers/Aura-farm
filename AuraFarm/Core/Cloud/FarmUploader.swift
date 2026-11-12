import Foundation
import Supabase

/// Sends a farm the helper mapped to the records, so a sample taken from it can be filed
/// against the land it came from.
///
/// One farm on the phone becomes a `farms` row and one `plots` row for each plot, numbered in
/// the order they are held on the phone.
///
/// shortcut: a plot deleted on the phone stays in `plots`, because this only upserts what the
/// phone still has. Delete the farm's rows that are not in the upload once a second helper can
/// edit the same farm and the records have to agree.
struct FarmUploader {
    var client: SupabaseClient

    enum Failure: LocalizedError {
        /// Config/Local.xcconfig names no project, so this build has no records to write to.
        case notConfigured
        /// No plot, or a plot with fewer than three corners, so there is no land to describe.
        case noLandMarked

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "This build is not set up to publish."
            case .noLandMarked:
                return "Mark at least one plot on the map before publishing this farm."
            }
        }
    }

    init?(client: SupabaseClient? = Cloud.client) {
        guard let client else { return nil }
        self.client = client
    }

    /// Writes the farm and its plots.
    ///
    /// Every row is an upsert keyed on the phone's own ids, so a helper who edits an outline
    /// and publishes again changes the rows rather than adding a second farm.
    func upload(_ farm: Farm) async throws {
        let rows = try farm.plots.enumerated().map { index, plot in
            guard let boundary = PlotBoundary.wellKnownText(for: plot.corners) else {
                throw Failure.noLandMarked
            }
            return PlotRow(plot: plot, farmID: farm.id, number: index + 1, boundary: boundary)
        }
        guard !rows.isEmpty else { throw Failure.noLandMarked }

        try await client.from("farms").upsert(FarmRow(farm: farm)).execute()
        try await client.from("plots").upsert(rows).execute()
    }
}

/// One row of `farms`.
struct FarmRow: Encodable, Equatable {
    var id: UUID
    var name: String
    var farmerName: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case farmerName = "farmer_name"
    }

    init(farm: Farm) {
        self.id = farm.id
        self.name = farm.name
        self.farmerName = farm.farmerName
    }
}

/// One row of `plots`.
struct PlotRow: Encodable, Equatable {
    /// The plot's own id on the phone, so publishing again changes this plot rather than
    /// adding a second one of the same land.
    var id: UUID
    var farmID: UUID
    var plotNumber: Int
    /// Well-known text, which PostGIS reads into the geography column.
    var boundary: String
    var areaHa: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case farmID = "farm_id"
        case plotNumber = "plot_number"
        case boundary
        case areaHa = "area_ha"
    }

    init(plot: Plot, farmID: UUID, number: Int, boundary: String) {
        self.id = plot.id
        self.farmID = farmID
        self.plotNumber = number
        self.boundary = boundary
        self.areaHa = PlotBoundary.hectares(of: plot.corners)
    }
}
