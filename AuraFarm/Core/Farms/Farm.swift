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

/// A farm the field helper looks after: whose it is and where the land lies.
///
/// The land is the corners the helper marked on the map, in the order they went round the
/// edge. The area is worked out from them, not stored, so it cannot disagree with the dots.
struct Farm: Codable, Identifiable, Equatable {
    var id = UUID()
    var farmerName: String
    var corners: [GeoPoint]
    var createdAt = Date()

    /// nil until there are at least three corners.
    var areaSquareMetres: Double? { LandGeometry.areaSquareMetres(of: corners) }
}
