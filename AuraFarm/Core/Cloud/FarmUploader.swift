import Foundation
import Supabase

/// Sends a farm the helper mapped to the records, so a sample taken from it can be filed
/// against the land it came from.
///
/// One farm on the phone becomes two rows: the farm, and the single plot that holds its
/// outline. The phone has no second plot to offer yet, so the plot is numbered 1.
struct FarmUploader {
    var client: SupabaseClient

    enum Failure: LocalizedError {
        /// Config/Local.xcconfig names no project, so this build has no records to write to.
        case notConfigured
        /// Fewer than three corners, so there is no land to describe.
        case noLandMarked

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "This build is not set up to publish."
            case .noLandMarked:
                return "Mark the land on the map before publishing this farm."
            }
        }
    }

    init?(client: SupabaseClient? = Cloud.client) {
        guard let client else { return nil }
        self.client = client
    }

    /// Writes the farm and its plot.
    ///
    /// Both are upserts keyed on the phone's own id for the farm, so a helper who edits an
    /// outline and publishes again changes the rows rather than adding a second farm.
    func upload(_ farm: Farm) async throws {
        guard let boundary = PlotBoundary.wellKnownText(for: farm.corners) else {
            throw Failure.noLandMarked
        }
        try await client.from("farms").upsert(FarmRow(farm: farm)).execute()
        try await client
            .from("plots")
            .upsert(PlotRow(farm: farm, boundary: boundary))
            .execute()
    }
}

/// One row of `farms`.
struct FarmRow: Encodable, Equatable {
    var id: UUID
    /// `farms.name` cannot be null and the phone never asks for one, so the farmer's name
    /// stands in. Give the form a farm name of its own and this stops being a copy.
    var name: String
    var farmerName: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case farmerName = "farmer_name"
    }

    init(farm: Farm) {
        self.id = farm.id
        self.name = farm.farmerName
        self.farmerName = farm.farmerName
    }
}

/// One row of `plots`: the only plot a phone-mapped farm has.
struct PlotRow: Encodable, Equatable {
    /// The farm's own id. One plot to a farm, so reusing it keeps publishing again from
    /// making a second plot of the same land.
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

    init(farm: Farm, boundary: String) {
        self.id = farm.id
        self.farmID = farm.id
        self.plotNumber = 1
        self.boundary = boundary
        self.areaHa = PlotBoundary.hectares(of: farm.corners)
    }
}
