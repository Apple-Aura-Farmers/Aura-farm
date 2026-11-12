import CoreGraphics
import Foundation

/// The numbers `ReadingConsistency` decides with. Data, not logic.
struct ReadingConsistencyThresholds {
    /// A new anchor offset may differ from (the previous anchor offset + this frame's
    /// frame-to-frame shift) by at most this share of the box side. PLACEHOLDER: not
    /// calibrated. The false jumps measured were 100–250 px above the prediction, and real
    /// readings stayed within a few px.
    var maxDisagreementOfBox: Double = 0.12
    /// Readings in a row replaced by the prediction before the pipeline commits the
    /// predicted offset as a hop and re-anchors. PLACEHOLDER: not calibrated.
    var maxPredictedInARow: Int = 5
}

/// What `ReadingConsistency` made of one reading.
enum ReadingVerdict: Equatable {
    /// The anchor registration agreed with the frame-to-frame movement.
    case measured(CGPoint)
    /// It did not (or gave nothing), so the last offset plus the frame-to-frame shift stands
    /// in for it.
    case predicted(CGPoint)
    /// Neither reading is available.
    case missing

    /// The word written in the CSV's `reading` column.
    var csvName: String {
        switch self {
        case .measured: "measured"
        case .predicted: "predicted"
        case .missing: "missing"
        }
    }

    /// The offset to hand the odometer; nil for `.missing`.
    var offset: CGPoint? {
        switch self {
        case .measured(let offset), .predicted(let offset): offset
        case .missing: nil
        }
    }
}

/// Rejects anchor readings that disagree with how far the picture moved since the last frame.
///
/// Hand-moved tests showed registration against the anchor sometimes returning a confident
/// wrong match (about 250 px) in one reading while the frame-to-frame shift was a few px. A
/// real move cannot do that, so such a reading is replaced by a prediction: the last accepted
/// offset plus this frame's frame-to-frame shift. Call `reset` whenever the anchor changes.
struct ReadingConsistency {
    var thresholds: ReadingConsistencyThresholds

    /// The last accepted offset from the anchor; zero right after anchoring.
    private(set) var lastAccepted = CGPoint.zero
    /// Readings in a row that were replaced by the prediction.
    private(set) var predictedStreak = 0

    init(thresholds: ReadingConsistencyThresholds = ReadingConsistencyThresholds()) {
        self.thresholds = thresholds
    }

    /// True once `maxPredictedInARow` readings in a row were predicted: the caller should
    /// commit the predicted offset as a hop, re-anchor, and `reset`.
    var mustCommit: Bool { predictedStreak >= thresholds.maxPredictedInARow }

    mutating func judge(anchorOffset: CGPoint?, frameShift: CGPoint?, boxSide: Double) -> ReadingVerdict {
        guard let frameShift else {
            // No frame-to-frame shift to check against, or to predict with.
            guard let anchorOffset else { return .missing }
            lastAccepted = anchorOffset
            predictedStreak = 0
            return .measured(anchorOffset)
        }
        let prediction = CGPoint(x: lastAccepted.x + frameShift.x, y: lastAccepted.y + frameShift.y)
        if let anchorOffset {
            let gap = hypot(
                Double(anchorOffset.x - prediction.x), Double(anchorOffset.y - prediction.y))
            if gap <= thresholds.maxDisagreementOfBox * boxSide {
                lastAccepted = anchorOffset
                predictedStreak = 0
                return .measured(anchorOffset)
            }
        }
        lastAccepted = prediction
        predictedStreak += 1
        return .predicted(prediction)
    }

    /// Call when the anchor changes: the next offset is measured from zero.
    mutating func reset() {
        lastAccepted = .zero
        predictedStreak = 0
    }
}
