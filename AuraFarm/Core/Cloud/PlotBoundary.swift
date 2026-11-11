import Foundation

/// Turns the corners a helper marked on the map into the text `plots.boundary` accepts.
///
/// PostGIS reads a geometry or geography column from well-known text, so the corners go up
/// as `SRID=4326;POLYGON(...)` rather than as numbers. The same text works whichever of the
/// two the column is, which is why it is used in place of GeoJSON.
enum PlotBoundary {
    /// Corners below this cannot make a polygon, and the form already refuses to save one.
    static let fewestCorners = 3

    /// nil when there are too few corners to enclose anything.
    static func wellKnownText(for corners: [GeoPoint]) -> String? {
        guard corners.count >= fewestCorners else { return nil }
        var ring = corners
        // A polygon ring has to come back to where it started. The map keeps the corners
        // open, because a repeated dot would be one the helper could drag away on its own.
        if ring.first != ring.last { ring.append(ring[0]) }
        // Longitude first: well-known text is x then y, and x is the one that goes east.
        let points = ring.map { "\(number($0.longitude)) \(number($0.latitude))" }
        return "SRID=4326;POLYGON((\(points.joined(separator: ", "))))"
    }

    /// Hectares, for `plots.area_ha`.
    ///
    /// Sent rather than left to the column's default, which only runs on insert: editing an
    /// outline and publishing again would otherwise keep the area the land had before.
    static func hectares(of corners: [GeoPoint]) -> Double? {
        guard let squareMetres = LandGeometry.areaSquareMetres(of: corners) else { return nil }
        return (squareMetres / 10_000 * 1000).rounded() / 1000
    }

    /// Fixed decimals, never exponent form, and never a comma for the decimal point: the
    /// text is parsed by Postgres, not read by anyone here. Eight places is about a
    /// millimetre.
    private static func number(_ value: Double) -> String {
        String(format: "%.8f", locale: nil, value)
    }
}
