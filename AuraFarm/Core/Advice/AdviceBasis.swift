import Foundation

/// The "Based on" line under the advice: what the sample's advice used, and what it left out.
///
/// PROVISIONAL: wording written for the prototype.
enum AdviceBasis {
    /// nil when nothing at all was counted.
    static func line(for context: AdviceContext) -> String? {
        guard !context.interpreted.isEmpty || !context.alsoSeen.isEmpty else { return nil }

        let unused = context.alsoSeen.reduce(0) { $0 + $1.count }
        if context.interpreted.isEmpty {
            let used = unused == 1 ? "1 organism wasn't used." : "\(unused) organisms weren't used."
            return "Nothing in this sample could be read yet. " + used
        }

        let total = context.interpreted.reduce(0) { $0 + $1.count }
        let kinds = context.interpretedKinds
        let frames = context.result.framesKept
        var parts = [
            "\(count(total, "organism")) (\(count(kinds, "kind"))) in \(count(frames, "frame"))",
            context.result.moisture.rawValue,
        ]
        if let stage = context.result.cropStage { parts.append(stage.label.lowercased()) }
        let plot = context.result.plotName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasHistory = !context.history.isEmpty && !plot.isEmpty
        if let soil = SoilInputs(context.result.soil) {
            let names = soil.readings.map(\.short).joined(separator: ", ")
            let part = "soil measurements (\(names))"
            parts.append(hasHistory ? part : "and " + part)
        }
        if hasHistory {
            parts.append("and \(count(context.history.count, "earlier sample")) of \(plot)")
        }

        var line = "Based on " + parts.joined(separator: ", ") + "."
        if unused > 0 {
            line += unused == 1 ? " 1 other wasn't used." : " \(unused) others weren't used."
        }
        return line
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
