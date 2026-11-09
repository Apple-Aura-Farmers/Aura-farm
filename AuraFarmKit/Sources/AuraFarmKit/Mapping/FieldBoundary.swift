import Foundation

/// One corner of a field, in degrees.
public struct FieldPoint: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// True for a point that can exist on Earth.
    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// The outline of a field, as clicked on a satellite map: its corners in order.
///
/// Stored as JSON in the farm records, so the shape survives schema changes and could later
/// travel in a report.
public struct FieldBoundary: Codable, Equatable, Hashable, Sendable {
    /// Corners in the order they were clicked. The last joins back to the first.
    public var corners: [FieldPoint]

    /// A field needs at least three corners to enclose any ground.
    public static let minimumCorners = 3

    /// Mean Earth radius in metres (IUGG).
    static let earthRadiusMetres = 6_371_008.8

    public init(corners: [FieldPoint]) {
        self.corners = corners
    }

    /// True when the outline encloses ground and every corner is a real place.
    public var isComplete: Bool {
        corners.count >= Self.minimumCorners && corners.allSatisfy(\.isValid)
    }

    /// The ground enclosed, in hectares, or nil for an outline with fewer than three corners.
    ///
    /// The corners are projected flat around their middle and the shoelace formula is applied.
    /// For a paddy a few hundred metres across the projection error is far below a click's
    /// worth of error on the map. An outline that crosses itself gives a wrong area; the editor
    /// does not stop that yet.
    public var areaHectares: Double? {
        guard isComplete else { return nil }
        let middle = center
        let metresPerDegreeLatitude = Self.earthRadiusMetres * .pi / 180
        let metresPerDegreeLongitude = metresPerDegreeLatitude * cos(middle.latitude * .pi / 180)
        let flat = corners.map { corner in
            (
                x: (corner.longitude - middle.longitude) * metresPerDegreeLongitude,
                y: (corner.latitude - middle.latitude) * metresPerDegreeLatitude
            )
        }
        var twiceArea = 0.0
        for index in flat.indices {
            let current = flat[index]
            let next = flat[(index + 1) % flat.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return abs(twiceArea) / 2 / 10_000
    }

    /// The average of the corners: a place inside a convex field to put its label.
    public var center: FieldPoint {
        guard !corners.isEmpty else { return FieldPoint(latitude: 0, longitude: 0) }
        let count = Double(corners.count)
        return FieldPoint(
            latitude: corners.map(\.latitude).reduce(0, +) / count,
            longitude: corners.map(\.longitude).reduce(0, +) / count
        )
    }

    /// The smallest box holding every corner, or nil with no corners.
    public var bounds: GeoBounds? {
        GeoBounds(points: corners)
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// nil when the data is not a boundary.
    public init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(FieldBoundary.self, from: data) else { return nil }
        self = decoded
    }
}

/// A box on the map, in degrees. Fields in Indonesia never cross the antimeridian, so a box
/// is simply the smallest and largest latitude and longitude.
public struct GeoBounds: Equatable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// nil with no points.
    public init?(points: [FieldPoint]) {
        guard let first = points.first else { return nil }
        self.init(
            minLatitude: points.map(\.latitude).min() ?? first.latitude,
            maxLatitude: points.map(\.latitude).max() ?? first.latitude,
            minLongitude: points.map(\.longitude).min() ?? first.longitude,
            maxLongitude: points.map(\.longitude).max() ?? first.longitude
        )
    }

    /// The box around several boxes, or nil when there are none.
    public static func union(_ boxes: [GeoBounds]) -> GeoBounds? {
        guard !boxes.isEmpty else { return nil }
        return GeoBounds(
            minLatitude: boxes.map(\.minLatitude).min() ?? 0,
            maxLatitude: boxes.map(\.maxLatitude).max() ?? 0,
            minLongitude: boxes.map(\.minLongitude).min() ?? 0,
            maxLongitude: boxes.map(\.maxLongitude).max() ?? 0
        )
    }

    public var center: FieldPoint {
        FieldPoint(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    /// Height and width in degrees, grown by `factor` so the outline is not against the edge,
    /// and never smaller than `minimumDegrees` so a single small field is not zoomed past the
    /// imagery. 0.002° is about 220 m.
    public func span(paddedBy factor: Double = 1.6, minimumDegrees: Double = 0.002) -> (
        latitude: Double, longitude: Double
    ) {
        (
            latitude: max((maxLatitude - minLatitude) * factor, minimumDegrees),
            longitude: max((maxLongitude - minLongitude) * factor, minimumDegrees)
        )
    }
}
