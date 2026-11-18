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
    var detectorModel = DetectorModel.v2.rawValue
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
