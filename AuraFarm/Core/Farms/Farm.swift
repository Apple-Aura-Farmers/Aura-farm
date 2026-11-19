import CoreLocation
import Foundation

/// A point on the map, kept as plain numbers so it saves as JSON.
struct GeoPoint: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// One worked piece of a farm's land: the corners the helper marked, in the order they went
/// round the edge. A farm is one or more of these.
struct Plot: Codable, Identifiable, Equatable {
    var id = UUID()
    /// What the helper calls this piece of land, which is usually where it is rather than
    /// what it grows. Empty on a plot marked before the form asked for one.
    var name = ""
    var corners: [GeoPoint]
    /// What the field helper has measured on this plot's soil, apart from the microscope tests:
    /// one entry per visit, in any order. Each plot has its own, because the readings are taken
    /// on the plot and differ from one to the next.
    var soilLog: [SoilMeasurements] = []

    /// The newest measurement with something in it, which the advice is written from. nil until
    /// the helper records something.
    var soil: SoilMeasurements? { SoilMeasurements.latest(in: soilLog) }

    /// When the helper last asked a scientist to look at this plot, if they have.
    var scientistAlertedAt: Date? { soilLog.compactMap(\.scientistAlertedAt).max() }

    /// nil until there are at least three corners.
    var areaSquareMetres: Double? { LandGeometry.areaSquareMetres(of: corners) }
}

extension Plot {
    init(id: UUID = UUID(), name: String = "", corners: [GeoPoint], soil: SoilMeasurements?) {
        self.init(id: id, name: name, corners: corners, soilLog: soil.map { [$0] } ?? [])
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, corners, soilLog
        /// A plot used to keep a single soil.
        case soil
    }

    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        id = try stored.decode(UUID.self, forKey: .id)
        name = try stored.decodeIfPresent(String.self, forKey: .name) ?? ""
        corners = try stored.decode([GeoPoint].self, forKey: .corners)
        if let log = try stored.decodeIfPresent([SoilMeasurements].self, forKey: .soilLog) {
            soilLog = log
        } else if let soil = try stored.decodeIfPresent(SoilMeasurements.self, forKey: .soil) {
            soilLog = [soil]
        }
    }

    func encode(to encoder: any Encoder) throws {
        var stored = encoder.container(keyedBy: CodingKeys.self)
        try stored.encode(id, forKey: .id)
        try stored.encode(name, forKey: .name)
        try stored.encode(corners, forKey: .corners)
        try stored.encode(soilLog, forKey: .soilLog)
    }
}

/// A farm the field helper looks after: what it is called, whose it is, and the plots it is
/// made of.
///
/// The area of a plot is worked out from its corners, not stored, so it cannot disagree with
/// the dots.
struct Farm: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var farmerName: String
    var plots: [Plot] = []
    var createdAt = Date()

    /// Every corner of every plot, for fitting a map around the whole farm.
    var allCorners: [GeoPoint] { plots.flatMap(\.corners) }

    /// The plots added up. nil until one of them has three corners.
    var areaSquareMetres: Double? {
        let areas = plots.compactMap(\.areaSquareMetres)
        return areas.isEmpty ? nil : areas.reduce(0, +)
    }

    /// Where a plot sits in the farm, counted from 1, which is what `plots.plot_number` holds
    /// and what the map draws on the land.
    func number(of plot: Plot) -> Int {
        (plots.firstIndex(where: { $0.id == plot.id }) ?? 0) + 1
    }

    /// What a plot is called on screen: its number, which is always there, and the name the
    /// helper gave it underneath.
    func title(of plot: Plot) -> String { "Plot \(number(of: plot))" }

    /// Whether this farmer already has a plot by this name, ignoring case and surrounding
    /// spaces. Two farmers may both have a "Tabanan": a plot name only has to tell one
    /// farmer's land apart.
    func hasPlot(named name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return plots.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

extension Farm {
    /// Keys as they were written before a farm had a name of its own, more than one plot, or
    /// its soil kept per plot.
    private enum StoredKey: String, CodingKey {
        case id, name, farmerName, corners, plots, createdAt, soil
    }

    /// Reads farms saved by an earlier version too, rather than letting the store give up on
    /// the whole file and lose every farm on the phone. Such a farm had a single outline and
    /// no name, so the outline becomes its first plot and the farmer's name stands in.
    init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: StoredKey.self)
        id = try stored.decode(UUID.self, forKey: .id)
        farmerName = try stored.decode(String.self, forKey: .farmerName)
        createdAt = try stored.decode(Date.self, forKey: .createdAt)
        name = try stored.decodeIfPresent(String.self, forKey: .name) ?? farmerName
        if let plots = try stored.decodeIfPresent([Plot].self, forKey: .plots) {
            self.plots = plots
        } else {
            let corners = try stored.decodeIfPresent([GeoPoint].self, forKey: .corners) ?? []
            plots = corners.isEmpty ? [] : [Plot(corners: corners)]
        }
        // Soil used to belong to the farm as a whole. It goes to the first plot, the land a
        // farm had before it could have more than one.
        if let soil = try stored.decodeIfPresent(SoilMeasurements.self, forKey: .soil),
            !plots.isEmpty, plots[0].soilLog.isEmpty
        {
            plots[0].soilLog = [soil]
        }
    }
}

/// Land already mapped, drawn under a new outline so it can be kept clear of it.
struct Neighbour: Identifiable, Equatable {
    /// The plot's own id.
    var id: UUID
    /// Whose land it is, for the label on the map.
    var label: String
    var corners: [GeoPoint]
}

extension Array where Element == Farm {
    /// Every plot of every farm as a neighbour, except the one being edited.
    func neighbours(excluding plotID: UUID? = nil) -> [Neighbour] {
        flatMap { farm in
            farm.plots.lazy
                .filter { $0.id != plotID }
                .map { Neighbour(id: $0.id, label: farm.name, corners: $0.corners) }
        }
    }
}

extension Farm {
    /// Where the farm's land is, for the line under the farmer's name: the first plot that was
    /// given a name, then the farm's own name when that is not just the farmer's again, and
    /// how much land there is when neither says anything.
    var locationLine: String {
        if let named = plots.first(where: { !$0.name.isEmpty }) { return named.name }
        if name.caseInsensitiveCompare(farmerName) != .orderedSame { return name }
        guard let area = areaSquareMetres else { return "No land marked yet" }
        let count = plots.count == 1 ? "1 plot" : "\(plots.count) plots"
        return count + " · " + LandGeometry.hectaresDescription(squareMetres: area)
    }
}

extension Array where Element == Farm {
    /// The farms the helper is looking for: matched on the farmer, the farm's name and the
    /// names of its plots, which are the three things a row shows. Nothing typed matches
    /// everything. Case and accents are ignored, so "wayan" finds "Pak Wayan".
    func matching(_ query: String) -> [Farm] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self }
        return filter { farm in
            farm.farmerName.localizedStandardContains(query)
                || farm.name.localizedStandardContains(query)
                || farm.plots.contains { $0.name.localizedStandardContains(query) }
        }
    }
}
