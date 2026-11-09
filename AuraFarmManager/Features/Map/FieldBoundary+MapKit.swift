import AuraFarmKit
import MapKit

extension FieldPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension FieldBoundary {
    var coordinates: [CLLocationCoordinate2D] {
        corners.map(\.coordinate)
    }
}

extension GeoBounds {
    /// A map region showing the whole box with a margin around it.
    var region: MKCoordinateRegion {
        let span = span()
        return MKCoordinateRegion(
            center: center.coordinate,
            span: MKCoordinateSpan(latitudeDelta: span.latitude, longitudeDelta: span.longitude)
        )
    }
}

/// Where the maps start when there is nothing drawn yet.
enum MapDefaults {
    /// Bali, the whole island. The team's farms are there; change it if they are not.
    static let startRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -8.40, longitude: 115.19),
        span: MKCoordinateSpan(latitudeDelta: 0.9, longitudeDelta: 1.1)
    )

    /// The region around every field of a farm that has an outline, or nil when none has.
    @MainActor
    static func region(around fields: [Field]) -> MKCoordinateRegion? {
        GeoBounds.union(fields.compactMap { $0.boundary?.bounds })?.region
    }

    /// Looks a place up by name, such as a farm's village, and returns the area to show.
    /// nil when nothing is found or there is no connection.
    static func region(searchingFor place: String) async -> MKCoordinateRegion? {
        let query = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = startRegion
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        if let item = response.mapItems.first {
            return MKCoordinateRegion(
                center: item.placemark.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        return response.boundingRegion
    }
}
