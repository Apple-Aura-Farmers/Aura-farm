import CoreGraphics
import Foundation

/// What an edge question was about when it was raised, so the answer applies to that edge even if
/// the line has drifted off the cross since.
enum EdgeQuestionSnapshot: Equatable {
    /// A line at the cross: where it was (guide fields), and its angle.
    case line(point: CGPoint, angleDegrees: Double)
    /// "Edge should be here. Confirm?": the predicted edge's position along the leg.
    case expected(edgeAlong: Double)
}

/// The numbers `EdgeQuestionBook` decides with. Data, not logic.
struct EdgeQuestionThresholds: Equatable {
    /// A question stays answerable this long after the ask last held (the line left the cross),
    /// so a tap on the card still reaches it. PLACEHOLDER: 4 s, about the time to read the card
    /// and tap; not calibrated.
    var graceSeconds = 4.0
}

/// One question the guide asked the helper.
struct EdgeQuestion: Equatable {
    var id: Int
    var snapshot: EdgeQuestionSnapshot
    var lastAskedAt: Double
}

/// The edge questions, one at a time, each with an id. The card on screen carries the id, and an
/// answer names it: an answer to a question that was answered, replaced or has expired is late and
/// changes nothing. Pure; time comes in with each call. Analysis queue only.
struct EdgeQuestionBook: Equatable {
    var thresholds = EdgeQuestionThresholds()
    private(set) var current: EdgeQuestion?
    private var nextID = 1

    /// The question to show now, if any.
    var currentID: Int? { current?.id }

    /// Called on every reading. While the guide asks, the question is raised (or kept, with its
    /// snapshot refreshed); once the ask stops it stays answerable for `graceSeconds`.
    mutating func update(asking: Bool, snapshot: EdgeQuestionSnapshot?, seconds: Double) {
        if asking, let snapshot {
            if var question = current {
                question.snapshot = snapshot
                question.lastAskedAt = seconds
                current = question
            } else {
                current = EdgeQuestion(id: nextID, snapshot: snapshot, lastAskedAt: seconds)
                nextID += 1
            }
        } else if let question = current, seconds - question.lastAskedAt > thresholds.graceSeconds {
            current = nil
        }
    }

    /// The route settled the edge itself (the rule confirmed it, or the leg ended): no question.
    mutating func close() { current = nil }

    /// An answer to question `id`. Returns the question when it is the one on screen (and ends
    /// it); nil when it is late.
    mutating func answer(id: Int) -> EdgeQuestion? {
        guard let question = current, question.id == id else { return nil }
        current = nil
        return question
    }
}
