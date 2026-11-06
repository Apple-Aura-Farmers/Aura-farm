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
        /// How many frames this one has been seen in. It is counted once this reaches
        /// `minimumSightings`.
        var sightings = 1
    }

    /// One thing the detector found in a frame.
    struct Found {
        var label: String
        var box: CGRect
        var confidence: Float
    }

    /// How far a detection may sit from where a track is expected and still be the same one,
    /// as a share of the track's own size. One body width.
    ///
    /// Measured against six recorded clips: boxes average 43 px across, and a detection's
    /// nearest match in the frame before sits 8 px away at the median but 113 px away at the
    /// third quartile, so the model moves what it finds about a good deal. Loosening this
    /// from half a width to one cut the count on a 23 second clip from 125 to 118 and from
    /// 152 to 138 on another; past one width it buys almost nothing and starts joining
    /// neighbours together.
    ///
    /// Not calibrated against a stage, and it is the slide's speed under a real microscope
    /// that should set it.
    var matchDistance: Double = 1.0

    /// How many frames a track is kept after it was last seen, before it is dropped. It
    /// covers the model missing something for a frame or two; a track dropped and then seen
    /// again counts as new.
    ///
    /// PLACEHOLDER: not calibrated.
    var patience = 5

    /// How many frames a thing has to be seen in before it is counted. Two, because the
    /// model puts up a box for a single frame often enough to swamp the count: on three
    /// clips, counting everything gave 125, 152 and 46, and counting only what was seen
    /// twice gave 71, 83 and 14. What is dropped is mostly flicker, but a real organism that
    /// crosses the edge of the frame in one frame is dropped with it.
    ///
    /// Measured on handheld footage, not on a stage, so it is a placeholder like the rest.
    var minimumSightings = 2

    private(set) var tracks: [Track] = []
    private(set) var countByLabel: [String: Int] = [:]
    private(set) var total = 0

    private var nextID = 1

    /// The tracks in the current frame that have been counted, for drawing. A box that has
    /// only been seen once is not drawn: it is as likely to be flicker as an organism, and an
    /// id on screen that never reaches the count would be a lie.
    var visible: [Track] {
        tracks.filter { $0.unseenFrames == 0 && $0.sightings >= minimumSightings }
    }

    /// Feed one frame.
    /// - Parameters:
    ///   - found: what the detector found in this frame.
    ///   - pictureMoved: how far the picture moved since the frame before, in pixels. A thing
    ///     that stayed put on the slide appears this much further along in this frame.
    /// - Returns: the tracks counted in this frame, which is what makes a frame worth keeping
    ///   a picture of.
    @discardableResult
    mutating func update(found: [Found], pictureMoved: CGPoint) -> [Track] {
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

        var counted: [Track] = []
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
            tracks[pair.track].sightings += 1
            if tracks[pair.track].sightings == minimumSightings {
                count(tracks[pair.track])
                counted.append(tracks[pair.track])
            }
        }

        for (index, detection) in found.enumerated() where !takenDetections.contains(index) {
            let track = Track(
                id: nextID,
                label: detection.label,
                box: detection.box,
                confidence: detection.confidence,
                unseenFrames: 0
            )
            tracks.append(track)
            nextID += 1
            if minimumSightings <= 1 {
                count(track)
                counted.append(track)
            }
        }

        tracks.removeAll { $0.unseenFrames > patience }
        return counted
    }

    private mutating func count(_ track: Track) {
        total += 1
        countByLabel[track.label, default: 0] += 1
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
