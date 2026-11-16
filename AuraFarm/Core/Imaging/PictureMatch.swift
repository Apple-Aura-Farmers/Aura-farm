import CoreGraphics
import Foundation

/// The numbers `PictureMatchCheck` decides with. Data, not logic.
struct PictureMatchThresholds {
    /// Consecutive agreeing readings needed before a match is trusted. PLACEHOLDER: not
    /// calibrated.
    var readingsToConfirm: Int = 3
    /// Each reading must equal the previous one plus the frame-to-frame shift, within this
    /// share of the box side (about 17 px on a 344 px box). PLACEHOLDER: not calibrated. On
    /// the 12 November stage runs, moving readings disagreed with that prediction by a median
    /// of 0 px and a 90th percentile of 1 px, so this is generous.
    var maxStepDisagreementOfBox: Double = 0.05
    /// A reading further than this share of the box side is not trusted, as for
    /// `HopOdometerThresholds.maxTrustedFractionOfBox`. PLACEHOLDER: not calibrated.
    var maxOffsetOfBox: Double = 0.4
    /// Give up after this many readings without a confirmation. PLACEHOLDER: not calibrated.
    var maxReadings: Int = 8
}

enum PictureMatchVerdict: Equatable {
    case pending
    case confirmed(CGPoint)
    case rejected
}

/// Confirms a match against a stored picture before trusting it. Vision sometimes returns a
/// confident wrong answer for a single reading, so a match counts only once a few readings in
/// a row agree with each other and with the frame-to-frame movement between them.
///
/// Once confirmed or rejected the verdict is sticky until `reset()`.
struct PictureMatchCheck {
    var thresholds: PictureMatchThresholds

    private var chainLength = 0
    private var chainLast: CGPoint?
    private var readingsFed = 0
    private var verdict = PictureMatchVerdict.pending

    init(thresholds: PictureMatchThresholds = PictureMatchThresholds()) {
        self.thresholds = thresholds
    }

    /// - Parameters:
    ///   - offset: where the stored picture sits against this frame, px; nil when Vision gave
    ///     nothing.
    ///   - frameShift: this frame's shift from the last, px; nil when unknown (then the view
    ///     is assumed still).
    ///   - boxSide: the registration box's side, px.
    mutating func feed(offset: CGPoint?, frameShift: CGPoint?, boxSide: Double) -> PictureMatchVerdict {
        guard verdict == .pending else { return verdict }
        readingsFed += 1

        if let offset, hypot(Double(offset.x), Double(offset.y)) <= thresholds.maxOffsetOfBox * boxSide {
            if let last = chainLast {
                let expected = CGPoint(
                    x: last.x + (frameShift?.x ?? 0), y: last.y + (frameShift?.y ?? 0))
                let gap = hypot(Double(offset.x - expected.x), Double(offset.y - expected.y))
                chainLength = gap <= thresholds.maxStepDisagreementOfBox * boxSide ? chainLength + 1 : 1
            } else {
                chainLength = 1
            }
            chainLast = offset
        } else {
            chainLength = 0
            chainLast = nil
        }

        if chainLength >= thresholds.readingsToConfirm, let chainLast {
            verdict = .confirmed(chainLast)
        } else if readingsFed >= thresholds.maxReadings {
            verdict = .rejected
        }
        return verdict
    }

    mutating func reset() {
        self = PictureMatchCheck(thresholds: thresholds)
    }
}
