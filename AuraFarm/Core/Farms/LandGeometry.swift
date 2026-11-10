import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// The sums behind a marked-out piece of land. Pure functions with no map or UI in them, so
/// they can be unit tested.
///
/// Corners are flattened onto a plane around a shared centre before any sum is done. At the
/// size of a farm the curve of the earth makes no difference worth measuring, and a flat plane
/// keeps the area and the crossing checks simple.
enum LandGeometry {
    /// Metres along the ground for one degree of latitude.
    private static let metresPerDegree = 6_371_008.8 * Double.pi / 180

    /// The average of the corners: a fair middle for a label, and the origin for flattening.
    static func centre(of corners: [GeoPoint]) -> GeoPoint? {
        guard !corners.isEmpty else { return nil }
        let count = Double(corners.count)
        return GeoPoint(
            latitude: corners.reduce(0) { $0 + $1.latitude } / count,
            longitude: corners.reduce(0) { $0 + $1.longitude } / count)
    }

    /// Corners as metres east and north of `origin`.
    private static func flattened(_ corners: [GeoPoint], around origin: GeoPoint) -> [CGPoint] {
        // A degree of longitude is shorter the further from the equator.
        let squeeze = cos(origin.latitude * .pi / 180)
        return corners.map {
            CGPoint(
                x: ($0.longitude - origin.longitude) * squeeze * metresPerDegree,
                y: ($0.latitude - origin.latitude) * metresPerDegree)
        }
    }

    private static func flattened(_ corners: [GeoPoint]) -> [CGPoint] {
        guard let origin = centre(of: corners) else { return [] }
        return flattened(corners, around: origin)
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

    /// True when two pieces of land share ground. Land that only touches along an edge, as
    /// next-door farms do, does not count.
    static func overlap(_ first: [GeoPoint], _ second: [GeoPoint]) -> Bool {
        guard first.count >= 3, second.count >= 3, let origin = centre(of: first + second)
        else { return false }
        let a = flattened(first, around: origin)
        let b = flattened(second, around: origin)

        // Edges of one cutting across edges of the other.
        for i in a.indices {
            for j in b.indices
            where edgesCross(a[i], a[(i + 1) % a.count], b[j], b[(j + 1) % b.count]) {
                return true
            }
        }
        // One piece lying wholly inside the other, with no edges crossing. The middle of each
        // is checked as well, which catches two outlines that match almost exactly.
        if b.contains(where: { contains(a, $0) }) || a.contains(where: { contains(b, $0) }) {
            return true
        }
        if let middleOfB = middle(of: b), contains(a, middleOfB) { return true }
        if let middleOfA = middle(of: a), contains(b, middleOfA) { return true }
        return false
    }

    /// Whether a spot on the map lies inside a piece of land. Used to tell which farm was tapped.
    static func contains(_ spot: GeoPoint, in corners: [GeoPoint]) -> Bool {
        guard corners.count >= 3, let origin = centre(of: corners) else { return false }
        let outline = flattened(corners, around: origin)
        return contains(outline, flattened([spot], around: origin)[0])
    }

    private static func middle(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let count = CGFloat(points.count)
        return CGPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count)
    }

    /// Whether `point` is inside `polygon`: a line out to the side crosses an odd number of
    /// edges.
    private static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[previous]
            if (a.y > point.y) != (b.y > point.y),
                point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
            {
                inside.toggle()
            }
            previous = index
        }
        return inside
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

    /// "0.42 ha"
    static func hectaresDescription(squareMetres: Double) -> String {
        let hectares = (squareMetres / 10_000).formatted(.number.precision(.fractionLength(2)))
        return "\(hectares) ha"
    }

    /// "0.42 ha · 4,200 m²"
    static func areaDescription(squareMetres: Double) -> String {
        let hectares = (squareMetres / 10_000).formatted(.number.precision(.fractionLength(2)))
        let metres = Int(squareMetres.rounded()).formatted()
        return "\(hectares) ha · \(metres) m²"
    }
}
