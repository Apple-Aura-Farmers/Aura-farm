import Foundation

/// Limits for the pre-recording check.
/// PLACEHOLDERS: none of these numbers are calibrated on a real microscope setup yet.
/// Set them from pilot footage (good and bad examples) before relying on them.
struct CaptureQualityThresholds {
    /// Mean brightness (0...255) below this counts as too dark.
    var minBrightness: Double = 60
    /// Variance of the Laplacian below this counts as blurry.
    var minSharpness: Double = 100
    /// Average frame-to-frame shift (pixels, full frame) above this counts as shaky.
    var maxShakePixels: Double = 3
    /// Consecutive bad readings needed before an issue is raised.
    var readingsToRaise: Int = 3
    /// Consecutive good readings needed before an issue is cleared.
    var readingsToClear: Int = 5
}

/// One measurement of the live image.
struct CaptureQualityReading: Equatable {
    /// Mean luma, 0...255.
    var brightness: Double
    /// Variance of the Laplacian of the luma plane. Higher means sharper.
    var sharpness: Double
    /// Average shift in pixels. nil until two frames have been compared.
    var shakePixels: Double?
}

/// Turns a stream of readings into a stable set of active issues.
/// Raising and clearing need several readings in a row, so the banner does not flicker.
/// Pure logic with no camera dependency, so it is unit tested.
final class CaptureQualityMonitor {
    let thresholds: CaptureQualityThresholds

    private(set) var activeIssues: Set<CaptureIssue> = []
    private(set) var readingCount = 0

    private var badStreak: [CaptureIssue: Int] = [:]
    private var goodStreak: [CaptureIssue: Int] = [:]

    init(thresholds: CaptureQualityThresholds = CaptureQualityThresholds()) {
        self.thresholds = thresholds
    }

    /// True once enough readings have arrived to trust the result.
    var hasSettled: Bool { readingCount >= thresholds.readingsToClear }

    /// True when the image has settled and no issue is active.
    var isReady: Bool { hasSettled && activeIssues.isEmpty }

    /// The issue to show, by priority.
    var topIssue: CaptureIssue? {
        CaptureIssue.allCases.first { activeIssues.contains($0) }
    }

    @discardableResult
    func update(with reading: CaptureQualityReading) -> Set<CaptureIssue> {
        readingCount += 1

        let isDark = reading.brightness < thresholds.minBrightness
        evaluate(.tooDark, isBad: isDark)

        // A dark image always looks blurry, so judge focus only when there is enough light.
        if !isDark {
            evaluate(.blurry, isBad: reading.sharpness < thresholds.minSharpness)
        }

        if let shake = reading.shakePixels {
            evaluate(.shaky, isBad: shake > thresholds.maxShakePixels)
        }

        return activeIssues
    }

    func reset() {
        activeIssues = []
        readingCount = 0
        badStreak = [:]
        goodStreak = [:]
    }

    private func evaluate(_ issue: CaptureIssue, isBad: Bool) {
        if isBad {
            badStreak[issue, default: 0] += 1
            goodStreak[issue] = 0
            if badStreak[issue, default: 0] >= thresholds.readingsToRaise {
                activeIssues.insert(issue)
            }
        } else {
            goodStreak[issue, default: 0] += 1
            badStreak[issue] = 0
            if goodStreak[issue, default: 0] >= thresholds.readingsToClear {
                activeIssues.remove(issue)
            }
        }
    }
}
