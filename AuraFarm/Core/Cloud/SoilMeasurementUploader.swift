import Foundation
import Supabase

/// Sends what the helper measured on each plot to `soil_measurements`, and reads it back.
///
/// The measurements are already on the phone before this runs, so a failure here costs the
/// sending and not the reading: a helper out of signal records the soil now and it goes up
/// with the next save that gets through.
struct SoilMeasurementUploader {
    var client: SupabaseClient

    enum Failure: LocalizedError {
        /// Config/Local.xcconfig names no project, so this build has no records to write to.
        case notConfigured
        /// The table is not in the project yet. supabase/soil-measurements.sql makes it.
        case noTable

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "This build is not set up to publish."
            case .noTable:
                return
                    "The records have nowhere to keep soil measurements yet. Run "
                    + "supabase/soil-measurements.sql on the project."
            }
        }
    }

    init?(client: SupabaseClient? = Cloud.client) {
        guard let client else { return nil }
        self.client = client
    }

    /// Writes a plot's soil, or takes the row away when there is nothing left to keep.
    ///
    /// An upsert on the plot, not on the measurement's own id: a plot has one soil, and a
    /// phone that was reinstalled would otherwise write a second row for the same land.
    func upload(_ soil: SoilMeasurements?, forPlot plotID: UUID, inFarm farmID: UUID) async throws {
        do {
            guard let soil, !soil.isUnrecorded else {
                try await client
                    .from("soil_measurements")
                    .delete()
                    .eq("plot_id", value: plotID)
                    .execute()
                return
            }
            try await client
                .from("soil_measurements")
                .upsert(StoredSoilRow(soil: soil, plotID: plotID, farmID: farmID), onConflict: "plot_id")
                .execute()
        } catch {
            throw Self.readable(error)
        }
    }

    /// Every plot's soil that this account can see, by plot.
    func fetch() async throws -> [UUID: SoilMeasurements] {
        do {
            let rows: [StoredSoilRow] =
                try await client
                .from("soil_measurements")
                .select(
                    "id, farm_id, plot_id, nitrogen, phosphorus, potassium, ph, organic_carbon_percent, "
                        + "fertilizer_product, fertilizer_kg_per_hectare, scientist_alerted_at, "
                        + "updated_at"
                )
                .execute()
                .value
            return Dictionary(
                rows.map { ($0.plotID, $0.measurements) }, uniquingKeysWith: { first, _ in first })
        } catch {
            throw Self.readable(error)
        }
    }

    /// Postgres says a missing table in a way nobody can act on, so it is said again here as
    /// the thing to do about it.
    private static func readable(_ error: any Error) -> any Error {
        "\(error)".contains("PGRST205") ? Failure.noTable : error
    }
}

/// One row of `soil_measurements`, in the column names the table uses.
struct StoredSoilRow: Codable {
    var id: UUID
    var farmID: UUID
    var plotID: UUID
    var nitrogen: Double?
    var phosphorus: Double?
    var potassium: Double?
    var ph: Double?
    var organicCarbonPercent: Double?
    var fertilizerProduct: String?
    var fertilizerKilogramsPerHectare: Double?
    var scientistAlertedAt: Date?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case farmID = "farm_id"
        case plotID = "plot_id"
        case nitrogen
        case phosphorus
        case potassium
        case ph
        case organicCarbonPercent = "organic_carbon_percent"
        case fertilizerProduct = "fertilizer_product"
        case fertilizerKilogramsPerHectare = "fertilizer_kg_per_hectare"
        case scientistAlertedAt = "scientist_alerted_at"
        case updatedAt = "updated_at"
    }

    init(soil: SoilMeasurements, plotID: UUID, farmID: UUID) {
        id = soil.id
        self.plotID = plotID
        self.farmID = farmID
        nitrogen = soil.nitrogen
        phosphorus = soil.phosphorus
        potassium = soil.potassium
        ph = soil.ph
        organicCarbonPercent = soil.organicCarbonPercent
        fertilizerProduct = soil.fertilizerProduct
        fertilizerKilogramsPerHectare = soil.fertilizerKilogramsPerHectare
        scientistAlertedAt = soil.scientistAlertedAt
        updatedAt = soil.updatedAt
    }

    var measurements: SoilMeasurements {
        SoilMeasurements(
            id: id, nitrogen: nitrogen, phosphorus: phosphorus, potassium: potassium, ph: ph,
            organicCarbonPercent: organicCarbonPercent, fertilizerProduct: fertilizerProduct,
            fertilizerKilogramsPerHectare: fertilizerKilogramsPerHectare,
            scientistAlertedAt: scientistAlertedAt, updatedAt: updatedAt)
    }
}
