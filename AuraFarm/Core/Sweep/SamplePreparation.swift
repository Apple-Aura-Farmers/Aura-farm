import Foundation

/// How every sample is made into a slide, as data, so the guide that shows it and the report
/// that records it cannot disagree.
///
/// A count is only worth as much as the slide it came from: the same soil mixed at a
/// different strength gives a different number of organisms per droplet. Changing anything
/// here changes what counts can be compared with, so say so in the pull request.
enum SamplePreparation {
    static let gramsOfSoil = 1.0
    static let millilitresOfWater = 10.0
    static let settlingMinutes = 1

    /// One line for the report, for example "1 g soil in 10 mL water, settled 1 min, one
    /// droplet under a cover slip".
    static var summary: String {
        "\(gramsOfSoil.formatted()) g soil in \(millilitresOfWater.formatted()) mL water, "
            + "settled \(settlingMinutes) min, one droplet under a cover slip"
    }
}
