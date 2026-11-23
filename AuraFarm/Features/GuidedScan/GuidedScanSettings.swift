import Foundation

/// The coverage choice asked once setup is done.
enum GuidedScanCoverage: Double, CaseIterable, Identifiable {
    case everySecondColumn = 1.6
    case everyColumn = 0.8

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .everySecondColumn: "Every 2nd column"
        case .everyColumn: "Every column"
        }
    }

    /// The coverage the Terraloka Stage recommends: at 100x a field is small, so every 2nd column
    /// keeps the scan short; at 40x every column is affordable.
    static func recommended(for objective: StageObjective) -> GuidedScanCoverage {
        objective == .x100 ? .everySecondColumn : .everyColumn
    }

    var detail: String {
        switch self {
        case .everySecondColumn: "Faster. Covers about half of the slide."
        case .everyColumn: "Slower. Covers the whole slide."
        }
    }
}

/// The knob rule with the lab's switches ("Swap knobs", "Reverse X", "Reverse Y"). The page's
/// engine settings are the lab's own (`LabSettings`); this is only the words' rule.
enum GuidedScanSettings {
    static var knobRule: KnobRule {
        func flag(_ key: String) -> Bool {
            UserDefaults.standard.object(forKey: "slideLab.\(key)") as? Bool ?? false
        }
        return KnobRule(
            xKnob: flag("knobSwap") ? .top : .bottom, reversesX: flag("knobReverseX"),
            reversesY: flag("knobReverseY"))
    }
}
