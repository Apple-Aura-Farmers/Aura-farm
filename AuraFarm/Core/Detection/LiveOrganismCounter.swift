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
        /// Seen while the stage is moved by hand: shown, never counted.
        case notCounted
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
        /// The detection box (frame px, from the top left) of each new entry, by entry id.
        var newBoxes: [Int: CGRect] = [:]
        /// At a preset stop: outside the stop's own cell, and lens dirt (neither is counted).
        var outsideCell = 0
        var dirt = 0
    }

    /// The preset stop a frame was taken at: its id, and the square of the frame it counts in.
    struct StopContext: Equatable {
        var id: Int
        var cell: CGRect
    }

    private var tally = OrganismTally()
    // Preset stops: the stop counted into now, the tracks of the one before it (for a result that
    // arrives late), and what each saw, for the lens dirt check.
    private var stopID: Int?
    private var parked: (id: Int, tracks: [OrganismTally.Track])?
    private var currentSeen: [StopSighting] = []
    private var previousSeen: [StopSighting] = []
    /// Detections of the last stop result that did not count (drawn grey).
    private(set) var ignoredBoxes: [VisibleBox] = []
    /// Results that came too late to belong to a stop the counter still knows.
    private(set) var lateStopDrops = 0
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
        } + ignoredBoxes
    }

    /// A frame that went to the detector.
    @discardableResult
    mutating func update(
        detections: [OrganismDetector.Detection], pictureMoved: CGPoint, trackerPosition: CGPoint,
        frameSize: CGSize, fieldCircle: FieldCircle?, crop: CGRect? = nil, seconds: Double,
        column: Int, fieldSide: Double = 1, stop: StopContext? = nil,
        thresholds: LiveCountThresholds = LiveCountThresholds()
    ) -> FrameResult {
        let width = Double(frameSize.width)
        let height = Double(frameSize.height)
        var result = FrameResult()
        var found: [OrganismTally.Found] = []
        // A result belongs to the stop its frame was taken at. A new stop clears the tracks (the
        // counts and the map stay); a result for the stop before it, arriving late, is counted
        // into that stop's own tracks; an older one is dropped.
        var currentTracks: [OrganismTally.Track]?
        if let stop {
            if let known = stopID, stop.id < known {
                guard let earlier = parked, earlier.id == stop.id else {
                    lateStopDrops += 1
                    lastResult = FrameResult()
                    return lastResult
                }
                currentTracks = tally.swapTracks(earlier.tracks)
            } else if stop.id != stopID {
                if let known = stopID { parked = (known, tally.tracks) }
                previousSeen = currentSeen
                currentSeen = []
                tally.clearTracks()
                stopID = stop.id
            }
        }
        let isLate = currentTracks != nil
        var seenHere: [StopSighting] = []
        var ignored: [VisibleBox] = []
        for detection in detections {
            let box = OrganismTally.Found(detection, frameWidth: width, frameHeight: height)
            let centre = CGPoint(x: box.box.midX, y: box.box.midY)
            let side = Double(max(box.box.width, box.box.height))
            if stop != nil { seenHere.append(StopSighting(label: box.label, centre: centre, side: side)) }
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
            if let stop {
                // Drawn grey, never counted: outside the stop's own cell, or lens dirt.
                let isDirt =
                    !isLate
                    && StopDirt.isDirt(
                        label: box.label, centre: centre, side: side, previous: previousSeen,
                        share: thresholds.stopDirtShare)
                if !stop.cell.contains(centre) || isDirt {
                    if isDirt, stop.cell.contains(centre) {
                        result.dirt += 1
                    } else {
                        result.outsideCell += 1
                    }
                    ignored.append(
                        VisibleBox(
                            id: 1_000_000 + ignored.count, label: box.label,
                            confidence: box.confidence, box: box.box, status: .seenOnce))
                    continue
                }
            }
            found.append(box)
        }
        result.found = found.count
        // Within a stop the picture does not move.
        let moved =
            stop != nil
            ? CGPoint.zero
            : CGPoint(x: carriedShift.x + pictureMoved.x, y: carriedShift.y + pictureMoved.y)
        carriedShift = .zero
        let counted = tally.update(found: found, pictureMoved: moved)
        if let tracks = currentTracks, let was = parked {
            // The late result's tracks go back to their own stop; the current stop's come back.
            parked = (was.id, tally.swapTracks(tracks))
        }
        if stop != nil {
            if isLate { previousSeen += seenHere } else { currentSeen += seenHere }
            ignoredBoxes = ignored
        } else {
            ignoredBoxes = []
        }
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
                let entry = map.add(
                    label: track.label, at: position, seconds: seconds, column: column,
                    fieldSide: fieldSide, confidence: Double(track.confidence))
                result.newEntries.append(entry)
                result.newBoxes[entry.id] = track.box
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
        stopID = nil
        parked = nil
        currentSeen = []
        previousSeen = []
        ignoredBoxes = []
        lateStopDrops = 0
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
    /// The model runs at most this often a second while counting (the "rate" skip). Analysed
    /// frames come every 0.11 to 0.12 s, so 5 a second lands on about every 2nd frame (4.1 to 4.5
    /// a second). PLACEHOLDER; source: the 17 Nov device runs, where the model ran 6.3 to 6.8 times
    /// a second on 94 to 97% of moving frames, and the 2-sighting rule: at 0.5 fields a second an
    /// organism is in view about 2 s, so about 8 to 9 looks.
    var maxModelRunsPerSecond = 5.0
    /// Drawn boxes only (never the count): hidden this long after the last frame the tracker gave
    /// a shift for. PLACEHOLDER; source: operator, 25 Nov 2026, boxes staying behind.
    var boxUntrackedSeconds = 0.4
    /// Drawn boxes are hidden when the detector's latest result is older than this. A still view
    /// is looked at again about every `refreshSeconds`, so its boxes stay. PLACEHOLDER; same source.
    var boxResultMaxSeconds = 1.5
    /// A stage move that never reports it settled holds the boxes back this long, then they may
    /// come back (results from before the move still do not). PLACEHOLDER.
    var boxMoveHoldSeconds = 10.0

    // Preset moves on the Terraloka stage: the model looks at the stops (see `PresetStopTracker`).
    // PLACEHOLDER; source: operator, 25 Nov 2026, blank or untracked views at a stop.
    /// At most this many looks at one stop, then "stop_done".
    var stopMaxLooks = 3
    /// A stop is held after its dwell until it has this many looks...
    var stopWantedLooks = 2
    /// ...or has lasted this long in all (a focus pause does not count).
    var stopMaxSeconds = 2.0
    /// A stop counts only in the square of this many boxes at the centre of the field circle (the
    /// preset path's own `stepFields`).
    var stopCellFields = 0.8
    /// A detection this close to one of the previous stop, as a share of its side, is lens dirt.
    var stopDirtShare = 0.5
    /// The log event of a stop waits this long for its last results.
    var stopEventDelaySeconds = 0.5
}

extension LiveOrganismCounter {
    /// The stage is known to be standing still: at a stop of the preset path, or in hand control
    /// with no move in flight (the preview).
    enum StillStage { case none, stop, hand }

    /// Why a frame is NOT sent to the detector while counting is on, or nil when it goes. The
    /// reasons are checked in this order: not_tracking, junk_frame, paused, no_sample, too_fast,
    /// unchanged, heat_critical, rate, heat. `maxModelRunsPerSecond` is the "rate" cap; nil is no
    /// cap.
    static func skipReason(
        tracking: TrackingState, isGhostOrSparseSkip: Bool, monitorPaused: Bool,
        viewClass: ViewClass, speedFraction: Double, stillSeconds: Double = 0,
        secondsSinceLastDetection: Double? = nil, maxModelRunsPerSecond: Double? = nil,
        heat: HeatMode = .normal,
        heatThresholds: HeatThresholds = HeatThresholds(),
        thresholds: LiveCountThresholds = LiveCountThresholds(),
        stillStage: StillStage = .none
    ) -> String? {
        // A stopped stage is known to be still: what the tracker and the view class say about the
        // picture moving or being followed does not apply (a dark view still does at a stop).
        let ignoresPicture = stillStage != .none
        if !ignoresPicture, tracking != .tracking { return "not_tracking" }
        if !ignoresPicture, isGhostOrSparseSkip { return "junk_frame" }
        if monitorPaused { return "paused" }
        if ignoresPicture {
            if stillStage == .stop, viewClass == .dark { return "no_sample" }
        } else if viewClass != .sample && viewClass != .thin {
            return "no_sample"
        }
        if !ignoresPicture, speedFraction > thresholds.countMaxSpeedFraction { return "too_fast" }
        if stillStage != .stop, stillSeconds >= thresholds.stillSecondsBeforeSkip - 1e-9,
            let since = secondsSinceLastDetection, since < thresholds.refreshSeconds - 1e-9
        {
            return "unchanged"
        }
        // Too hot: counting is paused, whatever the rate. Then the rate cap, which holds in every
        // other mode; then, while cooling down, the lower cap, so a frame between the two gaps is
        // "heat".
        if heat == .tooHot { return "heat_critical" }
        if let cap = maxModelRunsPerSecond, let since = secondsSinceLastDetection,
            since < 1 / cap - 1e-9
        {
            return "rate"
        }
        if heat == .coolDown, let since = secondsSinceLastDetection,
            since < 1 / heatThresholds.coolDownModelMaxPerSecond - 1e-9
        {
            return "heat"
        }
        return nil
    }
}
