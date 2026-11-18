import CoreGraphics
import Foundation

/// The only things the guided scan page says. Every `GuideInstruction` maps to one of these, so
/// the page never shows the guide's own wording.
enum HelperInstruction: Equatable {
    /// Turn this knob this way: "Bottom knob towards you".
    case turn(KnobRule.Words)
    /// "Hold still", with a ring while holding or confirming (0...1). `note` replaces the words.
    case stop(progress: Double?, note: String?)
    /// "Back a little: bottom knob away from you".
    case backALittle(KnobRule.Words)
    case refocus
    case phoneMoved
    case edgeFound
    case lastColumn
    case finished
    /// Setup, or the model loading.
    case waiting(String)
    /// "Is this the edge of the sample?" Yes / No.
    case question

    /// The one line the card shows.
    var text: String {
        switch self {
        case .turn(let words): words.text
        case .stop(_, let note): note ?? "Hold still"
        case .backALittle(let words): "Back a little: \(words.phrase)"
        case .refocus: "Turn the fine focus slowly until it's sharp"
        case .phoneMoved: "The phone moved. Line it back up"
        case .edgeFound: "Edge found"
        case .lastColumn: "Last column"
        case .finished: "Done"
        case .waiting(let text): text
        case .question: "Is this the edge of the sample?"
        }
    }

    /// The knob the drawing highlights, and the way; nil for a card with no knob.
    var knob: KnobRule.Words? {
        switch self {
        case .turn(let words), .backALittle(let words): words
        default: nil
        }
    }

    /// The ring's progress while holding still or confirming.
    var progress: Double? {
        if case .stop(let progress, _) = self { return progress }
        return nil
    }

    /// What makes two cards "the same" for steadiness: a ring moving or a clock ticking is the
    /// same card; another knob or another way is not.
    var identity: String {
        switch self {
        case .turn(let words): "turn \(words.text)"
        case .backALittle(let words): "back \(words.text)"
        case .stop(_, let note): "stop \(note ?? "")"
        case .refocus: "refocus"
        case .phoneMoved: "phoneMoved"
        case .edgeFound: "edgeFound"
        case .lastColumn: "lastColumn"
        case .finished: "finished"
        case .waiting(let text): "waiting \(text)"
        case .question: "question"
        }
    }

    /// Shown at once, whatever is on screen: the person must not keep turning (stop, the
    /// question), or has to hear it now (the phone moved, done).
    var isImmediate: Bool {
        switch self {
        case .stop, .question, .phoneMoved, .finished: true
        case .turn, .backALittle, .refocus, .edgeFound, .lastColumn, .waiting: false
        }
    }

    /// A one-off notice: shown at once and kept on screen for `CardSteadinessThresholds.noticeSeconds`.
    var isNotice: Bool {
        switch self {
        case .edgeFound, .lastColumn: true
        default: false
        }
    }

    /// The tap pattern for the card, played once when it comes up.
    var haptic: HelperHaptic {
        switch self {
        case .stop, .question: .firm
        case .backALittle: .threeLight
        case .edgeFound: .success
        case .finished: .longSuccess
        case .turn, .refocus, .phoneMoved, .lastColumn, .waiting: .none
        }
    }

    // MARK: From the guide

    /// The card for one guide instruction; nil for `captured`, which keeps the card on screen
    /// (the spot tick is its own haptic).
    ///
    /// - Parameters:
    ///   - arrow: the direction the guide's arrow points on the displayed picture (see
    ///     `GuideOverlayModel.arrowDirection`); nil when nothing is drawn.
    ///   - asksEdge: the edge question is showing (the lab's ✓ / ✗ buttons).
    ///
    /// The switch has no default on purpose: a new `GuideInstruction` does not compile until it
    /// is mapped here.
    static func make(
        for instruction: GuideInstruction, arrow: CGPoint?, rule: KnobRule, asksEdge: Bool
    ) -> HelperInstruction? {
        if asksEdge, !instruction.isFinishing { return .question }
        let words = arrow.flatMap { rule.words(forArrowDirection: $0) }
        switch instruction {
        case .findSample:
            return .waiting("Move onto the sample and focus")
        case .move, .travel, .farAway, .lineAhead, .lineLead, .notAnEdge:
            return words.map { .turn($0) }
        case .slowDown:
            // The speed bar shows the speed: the turn card stays.
            return nil
        case .holding(let progress), .checkingEdge(let progress):
            return .stop(progress: min(max(progress, 0), 1), note: nil)
        case .aligned, .edgeDetected:
            return .stop(progress: nil, note: nil)
        case .edgeReached:
            return .edgeFound
        case .tooFar, .otherWay, .edgeBehind, .missedSpot, .edgeGoBack, .checkEdge:
            return words.map { .backALittle($0) }
        case .refocus, .stillNoDetail:
            return .refocus
        case .nothingToFollow:
            return words.map { .backALittle($0) } ?? .refocus
        case .paused(let reason):
            return reason == .alignment ? .phoneMoved : .refocus
        case .captured:
            return nil
        case .expectedEdge:
            return .question
        case .stageLimit:
            return .stop(progress: nil, note: "The stage won't go further. Turning")
        case .finished:
            return .finished
        }
    }
}

extension GuideInstruction {
    /// The run is over: no question can still be open.
    fileprivate var isFinishing: Bool {
        if case .finished = self { return true }
        return false
    }
}

/// One pattern of taps for a card, as data; the page's player turns it into feedback.
enum HelperHaptic: Equatable {
    case none, oneLight, threeLight, firm, success, longSuccess

    enum Kind: Equatable { case light, firm, success }

    /// The taps and how long after the start each one lands, in seconds.
    var taps: [(kind: Kind, delay: Double)] {
        switch self {
        case .none: []
        case .oneLight: [(.light, 0)]
        case .threeLight: [(.light, 0), (.light, 0.15), (.light, 0.3)]
        case .firm: [(.firm, 0)]
        case .success: [(.success, 0)]
        // A long success: three in a row, so it is not mistaken for the short one.
        case .longSuccess: [(.success, 0), (.success, 0.25), (.success, 0.5)]
        }
    }
}

/// The numbers `CardSteadiness` decides with. Data, not logic.
struct CardSteadinessThresholds {
    /// A different card must be asked for this long, without a break, before it replaces the one
    /// on screen. PLACEHOLDER: 0.8 s, so a one-reading blip does not flicker the words.
    var steadySeconds = 0.8
    /// A notice ("Edge found", "Last column") stays this long before an ordinary card replaces
    /// it. PLACEHOLDER: long enough to read at arm's length.
    var noticeSeconds = 1.5
}

/// Keeps the card on screen from flickering: the guide's instruction can change on every
/// reading, a person cannot follow that. Pure; time comes in with each offer.
struct CardSteadiness {
    var thresholds = CardSteadinessThresholds()
    private(set) var shown: HelperInstruction?
    private var pending: (identity: String, since: Double)?
    private var noticeUntil = -Double.infinity

    /// Offers the card the guide wants now; returns the card to show, and whether it is new
    /// on screen (its haptic should play).
    mutating func offer(_ card: HelperInstruction, at seconds: Double) -> (
        card: HelperInstruction, isNew: Bool
    ) {
        guard let current = shown else { return show(card, at: seconds) }
        // The same card again: a ring moving or the text refreshed, shown at once.
        if card.identity == current.identity {
            pending = nil
            shown = card
            return (card, false)
        }
        if card.isImmediate || card.isNotice { return show(card, at: seconds) }
        // An ordinary card waits out a notice, then must hold steady.
        let since = pending?.identity == card.identity ? pending?.since ?? seconds : seconds
        pending = (card.identity, since)
        let steady = seconds - since >= thresholds.steadySeconds - 1e-9
        if steady, seconds >= noticeUntil - 1e-9 { return show(card, at: seconds) }
        return (current, false)
    }

    private mutating func show(_ card: HelperInstruction, at seconds: Double) -> (
        card: HelperInstruction, isNew: Bool
    ) {
        shown = card
        pending = nil
        noticeUntil = card.isNotice ? seconds + thresholds.noticeSeconds : -.infinity
        return (card, true)
    }

    /// Puts `card` on screen at once, as an answer to a tap does.
    mutating func force(_ card: HelperInstruction) {
        shown = card
        pending = nil
        noticeUntil = -.infinity
    }

    mutating func reset() {
        shown = nil
        pending = nil
        noticeUntil = -.infinity
    }
}
