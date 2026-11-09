import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// The sums behind a marked-out piece of land. Pure functions with no map or UI in them, so
/// they can be unit tested.
///
/// Corners are flattened onto a plane around their own centre before any sum is done. At the
/// size of a farm the curve of the earth makes no difference worth measuring, and a flat plane
/// keeps the area and the crossing check simple.
enum LandGeometry {
    /// Metres along the ground for one degree of latitude.
    private static let metresPerDegree = 6_371_008.8 * Double.pi / 180

    private static func flattened(_ corners: [GeoPoint]) -> [CGPoint] {
        guard !corners.isEmpty else { return [] }
        let count = Double(corners.count)
        let meanLatitude = corners.reduce(0) { $0 + $1.latitude } / count
        let meanLongitude = corners.reduce(0) { $0 + $1.longitude } / count
        // A degree of longitude is shorter the further from the equator.
        let squeeze = cos(meanLatitude * .pi / 180)
        return corners.map {
            CGPoint(
                x: ($0.longitude - meanLongitude) * squeeze * metresPerDegree,
                y: ($0.latitude - meanLatitude) * metresPerDegree)
        }
    }

    /// Area enclosed by the corners, in square metres. nil with fewer than three corners.
    static func areaSquareMetres(of corners: [GeoPoint]) -> Double? {
        guard corners.count >= 3 else { return nil }
        let points = flattened(corners)
        var twiceArea = 0.0
        for index in points.indices {
            let here = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += Double(here.x * next.y - next.x * here.y)
        }
        return abs(twiceArea) / 2
    }

    /// True when two edges of the outline cross each other, as when the dots were placed out of
    /// order. The area of such a shape means nothing, so it should not be saved.
    static func crossesItself(_ corners: [GeoPoint]) -> Bool {
        let points = flattened(corners)
        let count = points.count
        guard count >= 4 else { return false }
        for first in 0..<count {
            for second in (first + 1)..<count {
                // Neighbouring edges share a corner, so they only touch, never cross.
                if second == first + 1 || (first == 0 && second == count - 1) { continue }
                if edgesCross(
                    points[first], points[(first + 1) % count],
                    points[second], points[(second + 1) % count])
                {
                    return true
                }
            }
        }
        return false
    }

    private static func edgesCross(
        _ a1: CGPoint, _ a2: CGPoint, _ b1: CGPoint, _ b2: CGPoint
    ) -> Bool {
        /// Which side of the line from `start` to `end` the point `point` falls on.
        func side(_ start: CGPoint, _ end: CGPoint, _ point: CGPoint) -> CGFloat {
            (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
        }
        let d1 = side(b1, b2, a1)
        let d2 = side(b1, b2, a2)
        let d3 = side(a1, a2, b1)
        let d4 = side(a1, a2, b2)
        guard d1 != 0, d2 != 0, d3 != 0, d4 != 0 else { return false }
        return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0)
    }

    /// A map region with all the corners in it and some room round the edge. nil with no corners.
    static func region(fitting corners: [GeoPoint]) -> MKCoordinateRegion? {
        guard let first = corners.first else { return nil }
        var south = first.latitude
        var north = first.latitude
        var west = first.longitude
        var east = first.longitude
        for corner in corners {
            south = min(south, corner.latitude)
            north = max(north, corner.latitude)
            west = min(west, corner.longitude)
            east = max(east, corner.longitude)
        }
        // Never zoom in closer than a few tens of metres, even for a single dot.
        let minimumSpan = 0.0008
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (south + north) / 2, longitude: (west + east) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((north - south) * 1.5, minimumSpan),
                longitudeDelta: max((east - west) * 1.5, minimumSpan)))
    }

    /// "0.42 ha · 4,200 m²"
    static func areaDescription(squareMetres: Double) -> String {
        let hectares = (squareMetres / 10_000).formatted(.number.precision(.fractionLength(2)))
        let metres = Int(squareMetres.rounded()).formatted()
        return "\(hectares) ha · \(metres) m²"
    }
}
