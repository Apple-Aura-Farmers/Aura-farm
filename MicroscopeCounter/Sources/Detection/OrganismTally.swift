import CoreGraphics
import Foundation

/// A counted organism as the screen needs it: the id to show, and the box as a share of the
/// frame with the origin at the top left, which is what the preview layer converts from.
struct CountedBox: Identifiable, Equatable {
    var id: Int
    var label: String
    var box: CGRect
}

/// Counts what the detector finds across a sweep without counting anything twice.
///
/// The slide moves and the organisms mostly do not, so each thing found is given an id the
/// first time it is seen and then followed from frame to frame: every live track is moved by
/// how far the picture moved, and a detection that lands near where a track is expected is
/// that track again rather than a new one. A detection near nothing is new, takes the next
/// id, and adds one to the count.
///
/// Boxes and shifts are in frame pixels with the origin at the top left, the same way round
/// as `PanoramaStitcher` and `ShakeEstimator`.
///
/// Pure logic with no camera or model dependency, so it is unit tested.
struct OrganismTally {
    struct Track: Identifiable, Equatable {
        var id: Int
        var label: String
        var box: CGRect
        var confidence: Float
        /// Frames since this one was last seen. Zero means it is in the current frame.
        var unseenFrames: Int
    }

    /// One thing the detector found in a frame.
    struct Found {
        var label: String
        var box: CGRect
        var confidence: Float
    }

    /// How far a detection may sit from where a track is expected and still be the same one,
    /// as a share of the track's own size. Half a body width.
    ///
    /// PLACEHOLDER: not calibrated against a stage. Organisms that swim have to be followed
    /// through their own movement as well as the slide's, and how fast they swim between two
    /// frames is the number this should be set from.
    var matchDistance: Double = 0.5

    /// How many frames a track is kept after it was last seen, before it is dropped. It
    /// covers the model missing something for a frame or two; a track dropped and then seen
    /// again counts as new.
    ///
    /// PLACEHOLDER: not calibrated.
    var patience = 5

    private(set) var tracks: [Track] = []
    private(set) var countByLabel: [String: Int] = [:]
    private(set) var total = 0

    private var nextID = 1

    /// The tracks seen in the current frame, for drawing.
    var visible: [Track] { tracks.filter { $0.unseenFrames == 0 } }

    /// Feed one frame.
    /// - Parameters:
    ///   - found: what the detector found in this frame.
    ///   - pictureMoved: how far the picture moved since the frame before, in pixels. A thing
    ///     that stayed put on the slide appears this much further along in this frame.
    mutating func update(found: [Found], pictureMoved: CGPoint) {
        // Carry every track to where it should now be.
        for index in tracks.indices {
            tracks[index].box = tracks[index].box.offsetBy(dx: pictureMoved.x, dy: pictureMoved.y)
            tracks[index].unseenFrames += 1
        }

        // Nearest first, so a crowded patch matches the obvious pairs before the doubtful
        // ones. Each track and each detection is used at most once.
        var pairs: [(detection: Int, track: Int, distance: Double)] = []
        for (detectionIndex, detection) in found.enumerated() {
            for (trackIndex, track) in tracks.enumerated() where track.label == detection.label {
                let distance = Self.distance(from: detection.box, to: track.box)
                let allowed = matchDistance * Self.size(of: track.box)
                if distance <= allowed {
                    pairs.append((detectionIndex, trackIndex, distance))
                }
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var takenDetections = Set<Int>()
        var takenTracks = Set<Int>()
        for pair in pairs {
            guard !takenDetections.contains(pair.detection), !takenTracks.contains(pair.track)
            else { continue }
            takenDetections.insert(pair.detection)
            takenTracks.insert(pair.track)
            tracks[pair.track].box = found[pair.detection].box
            tracks[pair.track].confidence = found[pair.detection].confidence
            tracks[pair.track].unseenFrames = 0
        }

        for (index, detection) in found.enumerated() where !takenDetections.contains(index) {
            tracks.append(
                Track(
                    id: nextID,
                    label: detection.label,
                    box: detection.box,
                    confidence: detection.confidence,
                    unseenFrames: 0
                ))
            nextID += 1
            total += 1
            countByLabel[detection.label, default: 0] += 1
        }

        tracks.removeAll { $0.unseenFrames > patience }
    }

    mutating func reset() {
        tracks = []
        countByLabel = [:]
        total = 0
        nextID = 1
    }

    private static func distance(from one: CGRect, to other: CGRect) -> Double {
        hypot(one.midX - other.midX, one.midY - other.midY)
    }

    /// A box's size as one number: the mean of its sides.
    private static func size(of box: CGRect) -> Double {
        (box.width + box.height) / 2
    }
}
