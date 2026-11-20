import Foundation

/// The "Based on" line under the advice: what the sample's advice used, and what it left out.
///
/// PROVISIONAL: wording written for the prototype.
enum AdviceBasis {
    /// nil when nothing at all was counted. In the phone's language: the line is only shown,
    /// never given to the model or saved.
    static func line(for context: AdviceContext) -> String? {
        guard !context.interpreted.isEmpty || !context.alsoSeen.isEmpty else { return nil }

        let unused = context.alsoSeen.reduce(0) { $0 + $1.count }
        if context.interpreted.isEmpty {
            return unused == 1
                ? String(localized: "Nothing in this sample could be read yet. 1 organism wasn't used.")
                : String(localized: "Nothing in this sample could be read yet. \(unused) organisms weren't used.")
        }

        let total = context.interpreted.reduce(0) { $0 + $1.count }
        let kinds = context.interpretedKinds
        let frames = context.result.viewsLooked
        let counted = organisms(total)
        let kindCount = kindsText(kinds)
        let looked = views(frames, guided: context.result.isGuidedScan)
        var parts = [
            String(localized: "\(counted) (\(kindCount)) in \(looked)"),
            moisture(context.result.moisture),
        ]
        if let stage = context.result.cropStage { parts.append(stage.label.translated.lowercased()) }
        let plot = context.result.plotName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasHistory = !context.history.isEmpty && !plot.isEmpty
        if let soil = SoilInputs(context.result.soil) {
            let names = soil.readings.map(\.short.translated).joined(separator: ", ")
            let part = String(localized: "soil measurements (\(names))")
            parts.append(hasHistory ? part : String(localized: "and \(part)"))
        }
        if hasHistory {
            let earlier = earlierSamples(context.history.count)
            parts.append(String(localized: "and \(earlier) of \(plot)"))
        }

        let list = parts.joined(separator: ", ")
        var line = String(localized: "Based on \(list).")
        if unused > 0 {
            line +=
                " "
                + (unused == 1
                    ? String(localized: "1 other wasn't used.")
                    : String(localized: "\(unused) others weren't used."))
        }
        return line
    }

    private static func views(_ number: Int, guided: Bool) -> String {
        if guided {
            return number == 1 ? String(localized: "1 field of view") : String(localized: "\(number) fields of view")
        }
        return number == 1 ? String(localized: "1 frame") : String(localized: "\(number) frames")
    }

    private static func organisms(_ number: Int) -> String {
        number == 1 ? String(localized: "1 organism") : String(localized: "\(number) organisms")
    }

    private static func kindsText(_ number: Int) -> String {
        number == 1 ? String(localized: "1 kind") : String(localized: "\(number) kinds")
    }

    private static func earlierSamples(_ number: Int) -> String {
        number == 1 ? String(localized: "1 earlier sample") : String(localized: "\(number) earlier samples")
    }

    private static func moisture(_ moisture: SampleDetails.Moisture) -> String {
        switch moisture {
        case .flooded: return String(localized: "flooded")
        case .drained: return String(localized: "drained")
        }
    }
}
