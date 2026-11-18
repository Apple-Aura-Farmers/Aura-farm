import CoreGraphics
import Foundation

/// What the guide says on one reading, in the terms the guided scan page needs. Plain values, so
/// the page's logic runs in tests without a camera.
struct GuidedScanInput: Equatable {
    var seconds: Double
    var instruction: GuideInstruction
    /// The direction the arrow points on the displayed picture (`GuideOverlayModel.arrowDirection`).
    var arrow: CGPoint?
    /// The edge question is showing.
    var asksEdge: Bool
    var column: Int
    var lastColumn: Bool
    /// The slip's height measured from its edges, once known.
    var slipHeightFields: Double?
    var speedFraction: Double
    /// A spot is within `SpeedBandThresholds.nearCrossFields` of the cross.
    var spotNearCross: Bool
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
    var band: SpeedBand
}

/// Turns the guide's readings into the page: the card (steadied), its haptic, "Column k of N" and
/// the speed band. Pure; time comes in with each reading.
struct GuidedScanPresenter {
    var rule = KnobRule()
    /// Fields between columns, from the coverage choice.
    var coverageStep = 1.6
    var columnCount = ColumnCount()
    var speedThresholds = SpeedBandThresholds()
    private(set) var steadiness = CardSteadiness()
    private var lastCaptureCount = 0
    private var wasLastColumn = false

    mutating func reset() {
        steadiness.reset()
        lastCaptureCount = 0
        wasLastColumn = false
    }

    mutating func present(_ input: GuidedScanInput) -> GuidedScanDisplay {
        let band = SpeedBand.of(
            speedFraction: input.speedFraction, nearCross: input.spotNearCross,
            thresholds: speedThresholds)
        let ticked = input.captureCount > lastCaptureCount
        lastCaptureCount = input.captureCount

        var offered: HelperInstruction?
        if input.isFinished {
            offered = .finished
        } else if input.lastColumn, !wasLastColumn {
            // Said once, when the last column begins; the words stay in the column text.
            offered = .lastColumn
        } else {
            offered = HelperInstruction.make(
                for: input.instruction, arrow: input.arrow, rule: rule, asksEdge: input.asksEdge)
            // Too fast to follow a turn: the card says so instead.
            if case .turn = offered, band.asksForSlower { offered = .slower }
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
            column: max(input.column, 1), isLastColumn: input.lastColumn)
        return GuidedScanDisplay(
            card: card, haptic: haptic, columnText: "Column \(max(input.column, 1)) of \(count)",
            band: band)
    }
}
