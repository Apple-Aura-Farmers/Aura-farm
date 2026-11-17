import CoreGraphics
import Foundation

/// Every organism counted in a run, each at a fixed point on the SLIDE, so one seen again from a
/// neighbouring column is the same organism and not a new one.
///
/// Sign convention. The tracker's `position` is the CONTENT's displacement on the frame, px, in
/// the frame's axes (x right, y down; see `HopOdometer`): a stationary organism that sat at slide
/// point `q` shows at frame point `q + position` (content moving right by 40 px reads +40). So a
/// box seen at `offset` from the frame centre is at slide point `offset - position`. Two sightings
/// of the same organism at different positions give the same point; unit-tested both ways.
struct SlideOrganismMap {
    struct Entry: Identifiable, Equatable {
        var id: Int
        var label: String
        /// Slide point, px, in the tracker's axes.
        var position: CGPoint
        var firstSeenSeconds: Double
        var column: Int
    }

    /// A new organism within this of an entry with the same label is a repeat: the larger box side
    /// times `matchBoxShare`, but at least `minimumMatchPixels`. PLACEHOLDER: tracker drift between
    /// columns is the risk, which is why the lab shows the map and the tally counts side by side.
    /// Calibrate from `count_map_total` against `count_tally_total` on a run of known organisms.
    var matchBoxShare = 1.0
    var minimumMatchPixels = 30.0

    private(set) var entries: [Entry] = []
    private(set) var countByLabel: [String: Int] = [:]
    var total: Int { entries.count }

    /// The slide point of a box centre (frame px from the top left) seen with the tracker at
    /// `trackerPosition`, for a frame centred at `frameCentre`.
    static func slidePosition(
        boxCentre: CGPoint, frameCentre: CGPoint, trackerPosition: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: boxCentre.x - frameCentre.x - trackerPosition.x,
            y: boxCentre.y - frameCentre.y - trackerPosition.y)
    }

    /// The entry a new sighting repeats, if any: the nearest of the same label within reach.
    func match(label: String, at position: CGPoint, boxSide: Double) -> Entry? {
        let reach = max(matchBoxShare * boxSide, minimumMatchPixels)
        return entries.filter { $0.label == label }
            .map { ($0, hypot(Double($0.position.x - position.x), Double($0.position.y - position.y))) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
    }

    /// Adds a new organism.
    mutating func add(label: String, at position: CGPoint, seconds: Double, column: Int) -> Entry {
        let entry = Entry(
            id: entries.count + 1, label: label, position: position, firstSeenSeconds: seconds,
            column: column)
        entries.append(entry)
        countByLabel[label, default: 0] += 1
        return entry
    }

    mutating func reset() {
        entries = []
        countByLabel = [:]
    }
}
