import Observation
import QuartzCore

/// Turns the lab engine's published guide state into what the guided scan page shows. A thin
/// wrapper: every decision is in `GuidedScanPresenter`, which is pure and tested.
@Observable
@MainActor
final class GuidedScanSession {
    private(set) var display: GuidedScanDisplay?
    @ObservationIgnored private var presenter = GuidedScanPresenter()
    @ObservationIgnored private var sentWords = ""

    func start(coverage: GuidedScanCoverage, rule: KnobRule) {
        presenter = GuidedScanPresenter()
        presenter.rule = rule
        presenter.coverageStep = coverage.rawValue
        display = nil
        sentWords = ""
    }

    /// The person tapped Yes or No on the question card: the card changes at once, and the answer
    /// goes to the engine, which applies it to that question.
    func answer(_ feedback: EdgeFeedback, on model: ScanEngine) -> HelperHaptic {
        guard let id = display?.questionID else { return .none }
        model.answerEdge(feedback, questionID: id)
        let result = presenter.answered(
            yes: feedback == .yes, questionID: id, at: CACurrentMediaTime())
        display = result
        return result.haptic
    }

    /// Reads the engine's state now and updates the display; returns the haptic to play.
    func refresh(from model: ScanEngine) -> HelperHaptic {
        guard let overlay = model.overlayState.model else { return .none }
        let input = GuidedScanInput(
            seconds: CACurrentMediaTime(), instruction: overlay.instruction,
            arrow: overlay.arrowDirection, questionID: model.overlayState.questionID,
            column: overlay.column, lastColumn: overlay.lastColumn,
            slipHeightFields: model.guideInfo.slipHeightFields,
            sideInsetFields: model.guideInfo.sideInsetFields,
            captureCount: model.overlayState.captureCount, isFinished: overlay.isFinished,
            isTooHot: model.heatMode == .tooHot)
        let shown = presenter.present(input)
        if shown != display { display = shown }
        // The CSV's knob_words column: what the person was told, when it changes.
        let words = shown.card?.text ?? ""
        if words != sentWords {
            sentWords = words
            model.setHelperWords(words)
        }
        return shown.haptic
    }
}
