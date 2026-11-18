import CoreGraphics
import Foundation

/// One organism the helper's count includes, where it was (fields, in the trail's space).
struct RunMapOrganism: Codable, Equatable {
    var label: String
    var x: Double
    var y: Double
    var column: Int
    var seconds: Double

    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// A point of the run's path, fields in the trail's space.
struct RunMapPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

/// A line of the map: "left", "right", "top" or "bottom" edge segments, or a "point" (a confirmed
/// edge point, where both ends are the same).
struct RunMapEdge: Codable, Equatable {
    var kind: String
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
}

/// Which parts of the map are drawn: the switches above the map on the results screen. The map is
/// framed by everything in the record whatever is switched off, so it does not jump.
struct RunMapLayers: Equatable {
    var path = true
    var organisms = true
    var edges = true
    /// Only this type of organism is drawn (a tapped legend row); nil for all.
    var onlyType: String?
}

/// Everything the run map draws, in the trail's space (fields, the tracker's axes) and how that
/// space turns onto the screen. Pure, so a map can be redrawn from a saved run record alone.
struct RunMapContent: Equatable {
    /// The most path points a record keeps.
    static let maxPathPoints = 2000

    var path: [CGPoint] = []
    /// The spots the guide captured (live map only).
    var spots: [CGPoint] = []
    var edges: [RunMapEdge] = []
    var organisms: [RunMapOrganism] = []
    var mapping = ScreenMapping.asIs
    var mirrored = false
    var layers = RunMapLayers()

    /// What is drawn after the switches: the framing uses all of the content, the drawing these.
    var drawnPath: [CGPoint] { layers.path ? path : [] }
    var drawnEdges: [RunMapEdge] { layers.edges ? edges : [] }
    var drawnOrganisms: [RunMapOrganism] {
        guard layers.organisms else { return [] }
        return layers.onlyType.map { type in organisms.filter { $0.label == type } } ?? organisms
    }

    init(
        path: [CGPoint] = [], spots: [CGPoint] = [], edges: [RunMapEdge] = [],
        organisms: [RunMapOrganism] = [], mapping: ScreenMapping = .asIs, mirrored: Bool = false
    ) {
        self.path = path
        self.spots = spots
        self.edges = edges
        self.organisms = organisms
        self.mapping = mapping
        self.mirrored = mirrored
    }

    init(record: GuideRunRecord) {
        self.init(
            path: record.path.map { CGPoint(x: $0.x, y: $0.y) }, edges: record.edges,
            organisms: record.organisms, mapping: ScreenMapping(rawValue: record.mapMapping) ?? .asIs,
            mirrored: record.mapMirrored)
    }

    /// A trail-space point on the screen's axes (x right, y down), still in fields.
    func onScreen(_ point: CGPoint) -> CGPoint { mapping.onScreen(point, mirrored: mirrored) }

    /// Every point the map draws, in trail space.
    var allPoints: [CGPoint] {
        path + spots + organisms.map(\.point)
            + edges.flatMap { [CGPoint(x: $0.x1, y: $0.y1), CGPoint(x: $0.x2, y: $0.y2)] }
    }

    /// The box around everything, on the screen's axes, in fields; nil when empty.
    var screenBounds: CGRect? {
        let points = allPoints.map(onScreen)
        guard let first = points.first else { return nil }
        var minX = Double(first.x)
        var maxX = minX
        var minY = Double(first.y)
        var maxY = minY
        for point in points {
            minX = min(minX, Double(point.x))
            maxX = max(maxX, Double(point.x))
            minY = min(minY, Double(point.y))
            maxY = max(maxY, Double(point.y))
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `points` thinned to at most `limit`, keeping the first and the last, evenly.
    static func thinned(_ points: [CGPoint], to limit: Int = maxPathPoints) -> [RunMapPoint] {
        guard limit > 1, points.count > limit else {
            return points.map { RunMapPoint(x: Double($0.x), y: Double($0.y)) }
        }
        let stride = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map {
            let point = points[min(Int((Double($0) * stride).rounded()), points.count - 1)]
            return RunMapPoint(x: Double(point.x), y: Double(point.y))
        }
    }
}
