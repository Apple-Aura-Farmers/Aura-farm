import Foundation
import Supabase

/// Sends a farm the helper mapped to the records, so a sample taken from it can be filed
/// against the land it came from.
///
/// One farm on the phone becomes a `farms` row and one `plots` row for each plot, numbered in
/// the order they are held on the phone. It also reads them back, and removes the rows for a
/// farm or a plot the phone has deleted.
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
        // Plots the phone no longer has are rows nobody will replace, so publishing takes
        // them away rather than leaving land behind that the farm has given up.
        try await client
            .from("plots")
            .delete()
            .eq("farm_id", value: farm.id)
            .not("id", operator: .in, value: Self.list(rows.map(\.id)))
            .execute()
    }

    /// The bracketed list a PostgREST `in` filter wants. Without the brackets the filter is
    /// not parsed at all, and the ids are uuids, which need no quoting.
    static func list(_ ids: [UUID]) -> String {
        "(" + ids.map(\.uuidString).joined(separator: ",") + ")"
    }

    /// Every farm in the records this account can see, with its plots.
    ///
    /// A farm whose plots cannot be read comes back without them rather than not at all, so
    /// one unreadable boundary does not hide the rest.
    func fetch() async throws -> [Farm] {
        let farms: [FetchedFarm] =
            try await client
            .from("farms")
            .select("id, name, farmer_name, created_at")
            .execute()
            .value
        let plots: [FetchedPlot] =
            try await client
            .from("plots")
            .select("id, farm_id, plot_number, boundary")
            .order("plot_number")
            .execute()
            .value

        let byFarm = Dictionary(grouping: plots, by: \.farmID)
        return farms.map { farm in
            Farm(
                id: farm.id,
                name: farm.name,
                farmerName: farm.farmerName,
                plots: (byFarm[farm.id] ?? []).compactMap(\.plot),
                createdAt: farm.createdAt ?? .now
            )
        }
    }

    /// Takes a farm and its plots out of the records.
    ///
    /// The plots go first: a records setup that does not cascade would otherwise keep the
    /// farm by refusing to let go of the land hanging off it.
    func delete(_ farm: Farm) async throws {
        try await client.from("plots").delete().eq("farm_id", value: farm.id).execute()
        try await client.from("farms").delete().eq("id", value: farm.id).execute()
    }

    /// Takes one plot out of the records, for a farm that is staying.
    func delete(_ plot: Plot) async throws {
        try await client.from("plots").delete().eq("id", value: plot.id).execute()
    }
}

/// One `farms` row as it comes back.
struct FetchedFarm: Decodable {
    var id: UUID
    var name: String
    var farmerName: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case farmerName = "farmer_name"
        case createdAt = "created_at"
    }
}

/// One `plots` row as it comes back, its boundary still in the hex PostGIS hands over.
struct FetchedPlot: Decodable {
    var id: UUID
    var farmID: UUID
    var plotNumber: Int?
    var boundary: String?

    enum CodingKeys: String, CodingKey {
        case id, boundary
        case farmID = "farm_id"
        case plotNumber = "plot_number"
    }

    /// nil where the boundary is missing or is not a polygon this phone can draw.
    var plot: Plot? {
        guard let boundary, let corners = PlotBoundary.corners(fromHexBinary: boundary) else {
            return nil
        }
        return Plot(id: id, corners: corners)
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

    /// `created_by` is not sent. The column defaults to whoever is signed in, which is what
    /// the insert policy checks, and leaving it to the records means publishing a farm read
    /// back from somebody else changes the farm without taking it off them.
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
    ///
    /// The area is not sent with it: `plots.area_ha` is generated from this boundary by the
    /// records themselves, and a generated column refuses any value, even the right one.
    var boundary: String

    enum CodingKeys: String, CodingKey {
        case id
        case farmID = "farm_id"
        case plotNumber = "plot_number"
        case boundary
    }

    init(plot: Plot, farmID: UUID, number: Int, boundary: String) {
        self.id = plot.id
        self.farmID = farmID
        self.plotNumber = number
        self.boundary = boundary
    }
}
