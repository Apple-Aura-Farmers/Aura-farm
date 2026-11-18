import CoreGraphics
import Foundation

/// Counts organisms live while the guide runs, with no pictures kept: a frame-to-frame
/// `OrganismTally` (two sightings make an organism) plus a `SlideOrganismMap`, which stops the
/// same organism being counted again when the next column overlaps it.
///
/// Boxes are frame pixels from the top left. Pure logic, so it is unit tested.
struct LiveOrganismCounter {
    enum BoxStatus: Equatable {
        /// Counted by the tally and new on the map.
        case counted
        /// Seen in one frame so far.
        case seenOnce
        /// Counted by the tally but already on the map.
        case repeatOnMap
    }

    struct VisibleBox: Identifiable, Equatable {
        var id: Int
        var label: String
        var confidence: Float
        var box: CGRect
        var status: BoxStatus
    }

    /// What one analysed frame did, for the CSV.
    struct FrameResult: Equatable {
        var found = 0
        var outsideField = 0
        /// Dropped as the eyepiece disc, and as too big for the model's input (see
        /// `DetectionGuards`).
        var droppedDisc = 0
        var droppedBig = 0
        var newInTally = 0
        var newOnMap = 0
        var repeatOnMap = 0
        var newEntries: [SlideOrganismMap.Entry] = []
    }

    private var tally = OrganismTally()
    private(set) var map = SlideOrganismMap()
    /// Drop boxes whose centre is outside the field circle (the dark ring). On by default.
    var dropsOutsideField = true
    var guards = DetectionGuards()
    private(set) var discDrops = 0
    private(set) var bigDrops = 0

    private(set) var framesCounted = 0
    private(set) var framesSkippedByReason: [String: Int] = [:]
    private(set) var lastResult = FrameResult()
    /// Picture movement of skipped frames, passed on with the next counted frame so tracks still
    /// line up across the gap.
    private var carriedShift = CGPoint.zero
    /// Tally track id -> whether the map took it as new.
    private var isRepeat: [Int: Bool] = [:]

    var helperTotal: Int { map.total }
    var helperCountByLabel: [String: Int] { map.countByLabel }
    var tallyTotal: Int { tally.total }
    var tallyCountByLabel: [String: Int] { tally.countByLabel }

    /// How the tracker's frame shift becomes the tally's picture movement. NOT negated, unlike
    /// `PictureShift.pictureMoved`: `SlideTracker.frameShift` reads like its `position`, the
    /// way the CONTENT moved (content moving right by 6 px reads +6), which is what the tally
    /// wants (a thing that stayed put on the slide appears this much further along). Checked
    /// against a real `SlideTracker` on shifted frames in `LiveOrganismCounterTests`, both axes.
    static func pictureMoved(frameShift: CGPoint?) -> CGPoint {
        frameShift ?? .zero
    }

    /// The boxes in the current frame that are counted, or seen once, for drawing.
    var visibleBoxes: [VisibleBox] {
        tally.tracks.filter { $0.unseenFrames == 0 }.map { track in
            let status: BoxStatus
            if track.sightings < tally.minimumSightings {
                status = .seenOnce
            } else {
                status = isRepeat[track.id] == true ? .repeatOnMap : .counted
            }
            return VisibleBox(
                id: track.id, label: track.label, confidence: track.confidence, box: track.box,
                status: status)
        }
    }

    /// A frame that went to the detector.
    @discardableResult
    mutating func update(
        detections: [OrganismDetector.Detection], pictureMoved: CGPoint, trackerPosition: CGPoint,
        frameSize: CGSize, fieldCircle: FieldCircle?, crop: CGRect? = nil, seconds: Double,
        column: Int, fieldSide: Double = 1
    ) -> FrameResult {
        let width = Double(frameSize.width)
        let height = Double(frameSize.height)
        var result = FrameResult()
        var found: [OrganismTally.Found] = []
        for detection in detections {
            let box = OrganismTally.Found(detection, frameWidth: width, frameHeight: height)
            if dropsOutsideField, let circle = fieldCircle,
                hypot(Double(box.box.midX - circle.centre.x), Double(box.box.midY - circle.centre.y))
                    > circle.radius
            {
                result.outsideField += 1
                continue
            }
            switch guards.drop(box: box.box, crop: crop, circle: fieldCircle) {
            case .disc?:
                result.droppedDisc += 1
                continue
            case .big?:
                result.droppedBig += 1
                continue
            case nil:
                break
            }
            found.append(box)
        }
        result.found = found.count
        let moved = CGPoint(x: carriedShift.x + pictureMoved.x, y: carriedShift.y + pictureMoved.y)
        carriedShift = .zero
        let counted = tally.update(found: found, pictureMoved: moved)
        framesCounted += 1
        result.newInTally = counted.count
        for track in counted {
            let centre = CGPoint(x: track.box.midX, y: track.box.midY)
            let position = SlideOrganismMap.slidePosition(
                boxCentre: centre, frameCentre: CGPoint(x: width / 2, y: height / 2),
                trackerPosition: trackerPosition)
            let side = max(track.box.width, track.box.height)
            if map.match(label: track.label, at: position, boxSide: side) != nil {
                isRepeat[track.id] = true
                result.repeatOnMap += 1
            } else {
                isRepeat[track.id] = false
                result.newEntries.append(
                    map.add(
                        label: track.label, at: position, seconds: seconds, column: column,
                        fieldSide: fieldSide))
                result.newOnMap += 1
            }
        }
        discDrops += result.droppedDisc
        bigDrops += result.droppedBig
        lastResult = result
        return result
    }

    /// A frame that did not go to the detector, while counting is on.
    mutating func skip(pictureMoved: CGPoint, reason: String) {
        carriedShift = CGPoint(x: carriedShift.x + pictureMoved.x, y: carriedShift.y + pictureMoved.y)
        framesSkippedByReason[reason, default: 0] += 1
        lastResult = FrameResult()
    }

    mutating func reset() {
        tally.reset()
        map.reset()
        framesCounted = 0
        framesSkippedByReason = [:]
        discDrops = 0
        bigDrops = 0
        lastResult = FrameResult()
        carriedShift = .zero
        isRepeat = [:]
    }
}

/// The numbers live counting decides with. Data, not logic. PLACEHOLDER.
struct LiveCountThresholds {
    /// Frames faster than this are not sent to the detector. Source: the 16 Nov 2026 23:47 run,
    /// box sharpness at speed_fraction 0.10 to 0.15 was about 66% of still. Calibrate from the
    /// `det_ran` and `det_found` CSV columns against `speed_fraction`.
    var countMaxSpeedFraction = 0.15
    /// A view that has not moved for this long, and was looked at less than `refreshSeconds` ago,
    /// is not sent to the detector again. PLACEHOLDER; source: the guide's own stillness (edge
    /// holds are 2 s of it) and `MovementIndicators.stillSeconds`.
    var stillSecondsBeforeSkip = 0.3
    /// A still view is looked at again this often, so anything swimming into it is found.
    /// PLACEHOLDER.
    var refreshSeconds = 1.0
}

extension LiveOrganismCounter {
    /// Why a frame is NOT sent to the detector while counting is on, or nil when it goes. The
    /// reasons are checked in this order.
    static func skipReason(
        tracking: TrackingState, isGhostOrSparseSkip: Bool, monitorPaused: Bool,
        viewClass: ViewClass, speedFraction: Double, stillSeconds: Double = 0,
        secondsSinceLastDetection: Double? = nil,
        thresholds: LiveCountThresholds = LiveCountThresholds()
    ) -> String? {
        if tracking != .tracking { return "not_tracking" }
        if isGhostOrSparseSkip { return "junk_frame" }
        if monitorPaused { return "paused" }
        if viewClass != .sample && viewClass != .thin { return "no_sample" }
        if speedFraction > thresholds.countMaxSpeedFraction { return "too_fast" }
        if stillSeconds >= thresholds.stillSecondsBeforeSkip - 1e-9,
            let since = secondsSinceLastDetection, since < thresholds.refreshSeconds - 1e-9
        {
            return "unchanged"
        }
        return nil
    }
}
