import Foundation

/// Where the lab is with learning the eyepiece mask.
enum FieldState: Equatable {
    /// Collecting frames; 0...1.
    case learning(progress: Double)
    /// Learned and trusted: registration looks inside its rectangle.
    case ready(FieldMask)
    /// Learned but not trusted: registration falls back to the centre square.
    case untrusted(FieldMask)

    /// The mask, once learned (trusted or not).
    var mask: FieldMask? {
        switch self {
        case .learning: nil
        case .ready(let mask), .untrusted(let mask): mask
        }
    }

    /// The share of the frame that is open field, once learned.
    var openShare: Double? {
        switch self {
        case .learning: nil
        case .ready(let mask), .untrusted(let mask): mask.openShare
        }
    }
}
