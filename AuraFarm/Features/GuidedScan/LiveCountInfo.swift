import CoreGraphics
import Foundation

/// What the helper chose on the End run dialog.
enum EndRunAction { case now, afterColumn, cancel }

/// What the screen shows of the live count, published from the analysis queue.
struct LiveCountInfo: Equatable {
    struct LabelCount: Equatable, Identifiable {
        var label: String
        var map: Int
        var tally: Int
        var id: String { label }
        /// What is shown on screen; `label` stays the data.
        var display: String { OrganismDisplayName.label(label) }
    }

    struct Box: Equatable, Identifiable {
        var id: Int
        var label: String
        var confidence: Float
        /// Frame pixels from the top left.
        var rect: CGRect
        var status: LiveOrganismCounter.BoxStatus
    }

    /// Counting is on: the first spot of column 1 has been ticked and the run goes on.
    var isActive = false
    /// The helper's number: what the slide map counted.
    var total = 0
    var tallyTotal = 0
    /// One row per label seen, biggest map count first; labels with no count are left out.
    var labels: [LabelCount] = []
    var boxes: [Box] = []
    /// What the detector sees while the stage is moved by hand (never counted), and whether
    /// that is what the boxes show now.
    var previewBoxes: [Box] = []
    var isPreviewing = false
    /// Every organism the helper's count includes, on the map (fields, the trail's space).
    var dots: [RunMapOrganism] = []
    var frameSize = CGSize.zero
    var framesCounted = 0
    var framesSkipped: [String: Int] = [:]
    /// A new organism was counted: a counter for the soft haptic (at most one per 0.5 s).
    var hapticCount = 0
    /// Why counting cannot run (the model did not open); nil otherwise.
    var problem: String?
    /// The model counting ("v1" or "v2"), the boxes the guards dropped, how long the model took
    /// to open, and whether it is still opening.
    var detectorModel = DetectorModel.v3.rawValue
    var detectorUnits = DetectorUnits.neuralEngine.rawValue
    var discDrops = 0
    var bigDrops = 0
    var loadMilliseconds: Double?
    var isLoadingModel = false

    /// "Nematode 5 · Volvox 7 · Euglenoid 2", most first.
    static func line(_ labels: [LabelCount], limit: Int? = nil) -> String {
        let shown = labels.filter { $0.map > 0 }
        let top = limit.map { Array(shown.prefix($0)) } ?? shown
        var text = top.map { "\($0.display) \($0.map)" }.joined(separator: " · ")
        if shown.count > top.count { text += " · +\(shown.count - top.count) more" }
        return text
    }

    static func organisms(_ total: Int) -> String {
        total == 1 ? "1 organism" : "\(total) organisms"
    }
}

/// Which of the detector's boxes are drawn now, and where. Drawing only: the tracks, the tally and
/// the map never see it. All times are on the run's clock.
struct LiveBoxGate {
    var now: Double
    /// The last frame the tracker gave a shift for; nil if none yet.
    var trackedAt: Double?
    /// A result taken from a frame before this is not drawn: the stage started a move (infinity
    /// while it has not settled) or settled since the frame was taken.
    var notBefore = -Double.infinity
    var thresholds = LiveCountThresholds()

    /// `boxes` of the result taken at `resultAt`, moved by `shift` (how far the picture moved
    /// since), without those whose moved centre is outside `circle`. Nothing when the result is too
    /// old, was taken before the gate, or the tracker has not given a shift for too long.
    func shown(
        _ boxes: [LiveCountInfo.Box], shift: CGPoint, resultAt: Double?, circle: FieldCircle?
    ) -> [LiveCountInfo.Box] {
        guard !boxes.isEmpty, let resultAt, resultAt >= notBefore,
            now - resultAt <= thresholds.boxResultMaxSeconds,
            let trackedAt, now - trackedAt <= thresholds.boxUntrackedSeconds
        else { return [] }
        return boxes.compactMap { box in
            var moved = box
            moved.rect = box.rect.offsetBy(dx: shift.x, dy: shift.y)
            if let circle,
                hypot(Double(moved.rect.midX - circle.centre.x), Double(moved.rect.midY - circle.centre.y))
                    > circle.radius
            {
                return nil
            }
            return moved
        }
    }
}

/// The Terraloka stage's latest move, as far as drawing the boxes needs it. Times are capture
/// times. Settling twice, or with no move in progress, does nothing.
struct StageMoveWatch {
    private var move: (startedAt: Double, settledAt: Double?)?

    mutating func start(at time: Double) { move = (time, nil) }

    /// The move ended (position, done, stop, an error, a resync, a disconnect). False when there
    /// was no move in progress.
    @discardableResult
    mutating func settle(at time: Double) -> Bool {
        guard var current = move, current.settledAt == nil else { return false }
        current.settledAt = time
        move = current
        return true
    }

    /// Results from frames taken before this (run clock) are not drawn: infinity while the move is
    /// on, the settle time after it; a move that never settled releases after `holdSeconds`.
    func notBefore(now: Double, origin: Double, holdSeconds: Double) -> Double {
        guard let move else { return -.infinity }
        if let settled = move.settledAt { return settled - origin }
        return now - move.startedAt < holdSeconds ? .infinity : move.startedAt - origin
    }
}

extension LiveOrganismCounter {
    /// The tracker really followed the picture on this frame: tracking, with a shift, and not a
    /// frame it only carried over (ghost, sparse_skip). Only then does the picture's shift move
    /// the boxes drawn, and the frame count as tracked for hiding them.
    static func isFollowed(tracking: TrackingState, frameShift: CGPoint?, reading: String) -> Bool {
        tracking == .tracking && frameShift != nil && reading != "ghost" && reading != "sparse_skip"
    }
}
