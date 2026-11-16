import Foundation

/// The tests the team runs in the slide movement lab, each with what to do on screen.
enum SlideLabTest: String, CaseIterable, Identifiable {
    case free, mapping, drift, labels, dropSize, stops

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .mapping: "1 · Mapping"
        case .drift: "2 · Drift"
        case .labels: "3 · Labels"
        case .dropSize: "4 · Drop size"
        case .stops: "5 · Stops"
        }
    }

    var instruction: String {
        switch self {
        case .free: "Move freely. Nothing special is being tested."
        case .mapping: "Slide one way slowly. Pick the mapping where the dot moves the same way."
        case .drift:
            "Centre a landmark, tap Mark start, go 3–5 fields (yellow box widths) away and come back to it, then Mark end."
        case .labels:
            "Choose a label and hold the view there for about 10 seconds. Repeat in 3 places."
        case .dropSize: "Start outside the drop, cross it edge to edge in one slow pass, stop outside."
        case .stops:
            "Move, then stop and hold until the still timer passes 2 seconds. Do it 10 times."
        }
    }

    /// Goes in the CSV file name and in each row.
    var fileSlug: String {
        switch self {
        case .dropSize: "drop-size"
        default: rawValue
        }
    }
}
