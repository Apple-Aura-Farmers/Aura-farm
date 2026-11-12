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
    var corners: [GeoPoint]

    /// nil until there are at least three corners.
    var areaSquareMetres: Double? { LandGeometry.areaSquareMetres(of: corners) }
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

    /// Where a plot sits in the farm, counted from 1, which is what `plots.plot_number` holds.
    func number(of plot: Plot) -> Int {
        (plots.firstIndex(where: { $0.id == plot.id }) ?? 0) + 1
    }
}

extension Farm {
    /// Keys as they were written before a farm had a name of its own or more than one plot.
    private enum StoredKey: String, CodingKey {
        case id, name, farmerName, corners, plots, createdAt
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
