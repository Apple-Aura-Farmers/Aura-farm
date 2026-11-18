import CoreGraphics
import Foundation

/// What the guide says on one reading, in the terms the guided scan page needs. Plain values, so
/// the page's logic runs in tests without a camera.
struct GuidedScanInput: Equatable {
    var seconds: Double
    var instruction: GuideInstruction
    /// The direction the arrow points on the displayed picture (`GuideOverlayModel.arrowDirection`).
    var arrow: CGPoint?
    /// The edge question is on the card, with its id (`EdgeQuestionBook`); nil when none.
    var questionID: Int?
    var column: Int
    var lastColumn: Bool
    /// The slip's height measured from its edges, once known.
    var slipHeightFields: Double?
    /// How far the first and last columns sit inside the side edges, in fields; nil until known.
    var sideInsetFields: Double?
    /// Spots ticked so far; a rise is a tick.
    var captureCount: Int
    var isFinished: Bool
}

/// What the page shows and plays after one reading.
struct GuidedScanDisplay: Equatable {
    var card: HelperInstruction?
    var haptic: HelperHaptic
    /// "Column 3 of 9".
    var columnText: String
    /// The edge question the card shows, by id; nil when the card is not the question.
    var questionID: Int?
}

/// Turns the guide's readings into the page: the card (steadied), its haptic and "Column k of N".
/// The speed is the lab's own bar, drawn from the engine; nothing here. Pure; time comes in with each reading.
struct GuidedScanPresenter {
    var rule = KnobRule()
    /// Fields between columns, from the coverage choice.
    var coverageStep = 1.6
    var columnCount = ColumnCount()
    private(set) var steadiness = CardSteadiness()
    private var lastCaptureCount = 0
    private var wasLastColumn = false
    /// Questions the person has answered: the card is never the question again for one of them,
    /// even if a stale reading still carries its id.
    private var answeredQuestions: Set<Int> = []
    /// The last ordinary card (not a question or a notice), for "No" to go back to.
    private var lastOrdinary: HelperInstruction?
    private var lastColumnText = ""

    mutating func reset() {
        steadiness.reset()
        lastCaptureCount = 0
        wasLastColumn = false
        answeredQuestions = []
        lastOrdinary = nil
    }

    /// The person tapped Yes or No on question `id`: the card changes at once, without waiting for
    /// the next reading. Yes is "Edge found" (with its haptic); No goes back to the card before
    /// the question.
    mutating func answered(yes: Bool, questionID id: Int, at seconds: Double) -> GuidedScanDisplay {
        answeredQuestions.insert(id)
        var haptic = HelperHaptic.none
        if yes {
            let result = steadiness.offer(.edgeFound, at: seconds)
            haptic = result.isNew ? result.card.haptic : .none
        } else if let card = lastOrdinary {
            steadiness.force(card)
        } else {
            steadiness.reset()
        }
        return GuidedScanDisplay(
            card: steadiness.shown, haptic: haptic, columnText: lastColumnText, questionID: nil)
    }

    mutating func present(_ input: GuidedScanInput) -> GuidedScanDisplay {
        let ticked = input.captureCount > lastCaptureCount
        lastCaptureCount = input.captureCount

        let asking = input.questionID.map { !answeredQuestions.contains($0) } ?? false
        var offered: HelperInstruction?
        if input.isFinished {
            offered = .finished
        } else if input.lastColumn, !wasLastColumn {
            // Said once, when the last column begins; the words stay in the column text.
            offered = .lastColumn
        } else {
            offered = HelperInstruction.make(
                for: input.instruction, arrow: input.arrow, rule: rule, asksEdge: asking)
        }
        wasLastColumn = input.lastColumn

        var haptic = HelperHaptic.none
        var card = steadiness.shown
        if let offered {
            let result = steadiness.offer(offered, at: input.seconds)
            card = result.card
            if result.isNew { haptic = result.card.haptic }
        }
        if haptic == .none, ticked { haptic = .oneLight }

        let count = columnCount.shown(
            step: coverageStep, measuredHeightFields: input.slipHeightFields,
            column: max(input.column, 1), isLastColumn: input.lastColumn,
            sideInsetFields: input.sideInsetFields)
        if let card, card != .question, !card.isNotice { lastOrdinary = card }
        lastColumnText = "Column \(max(input.column, 1)) of \(count)"
        return GuidedScanDisplay(
            card: card, haptic: haptic, columnText: lastColumnText,
            questionID: card == .question ? input.questionID : nil)
    }
}
