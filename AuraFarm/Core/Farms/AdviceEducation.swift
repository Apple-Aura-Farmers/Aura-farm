import Foundation

/// The short "About these measurements" education shown with the advice, in the app and in the
/// report. Built from the farm's recorded measurements only, from the fixed text in
/// `SoilEducation` and `FertilizerType`, so the screen and the PDF say exactly the same thing and
/// Apple Intelligence never writes any of it.
///
/// It is general information about each measurement and what its band may mean. It is not a
/// diagnosis of the field, and the steps of the advice are chosen elsewhere.
struct AdviceEducation: Equatable, Sendable {
    /// One recorded measurement.
    struct Item: Equatable, Sendable {
        let name: String
        /// "6.5" or "60 mg/kg".
        let value: String
        /// "Low", "Standard", "High" or "Excessive".
        let band: String
        let tone: SoilTone
        let whatItDoes: String
        /// What a reading in this band may mean.
        let meaning: String
        let whyStandardHelps: String
        /// What might be done. nil when the reading needs nothing.
        let action: String?
        /// How the reading was taken, such as "Field probe or kit · Drained or dry when measured".
        let context: String?
        /// The reading and its standard, for drawing where it sits.
        let number: Double
        let standard: SoilStandard
    }

    /// The recorded fertilizer kind.
    struct Fertilizer: Equatable, Sendable {
        let label: String
        let definition: String
        /// nil for "Not sure" and "No fertilizer recorded".
        let education: String?
        /// Product and amount as recorded, for the report's table. Never sent to the model.
        let details: String?
        /// How the kind sits against paddy research, and one line on what it does. nil for the
        /// two choices that say nothing about the fertilizer.
        var tone: SoilTone? = nil
        var verdict: String? = nil
        var effect: String? = nil
    }

    let items: [Item]
    let fertilizer: Fertilizer?
    /// The flooded-rice pH caveat, when there is a pH reading.
    let phCaveat: String?

    /// Said under the education, wherever it is shown.
    static let disclaimer =
        "General information about each measurement, not a diagnosis of this field. The standards are provisional and have not been reviewed by an agronomist."

    /// nil when nothing with education was recorded.
    init?(_ soil: SoilMeasurements?) {
        guard let soil else { return nil }
        var items: [Item] = []
        for row in soil.rows {
            guard let band = row.band, let education = row.education, let note = row.note,
                let standard = row.standard
            else { continue }
            items.append(
                Item(
                    name: Self.name(of: row.label), value: row.value, band: band.label, tone: note.tone,
                    whatItDoes: education.whatItDoes,
                    meaning: education.meaning ?? education.whyStandardHelps,
                    whyStandardHelps: education.whyStandardHelps, action: education.action,
                    context: row.context, number: row.number ?? 0, standard: standard))
        }
        let fertilizer = soil.fertilizerType.map { type in
            let details = [
                soil.fertilizerProduct,
                soil.fertilizerKilogramsPerHectare.map {
                    "\($0.formatted(.number.precision(.fractionLength(0...2)))) kg/ha"
                },
            ].compactMap { $0 }
            return Fertilizer(
                label: type.label, definition: type.definition,
                education: type.education.map { $0 + " " + FertilizerType.sharedNote },
                details: details.isEmpty ? nil : details.joined(separator: " · "),
                tone: type.tone, verdict: type.verdict, effect: type.effect)
        }
        guard !items.isEmpty || fertilizer != nil else { return nil }
        self.items = items
        self.fertilizer = fertilizer
        self.phCaveat = soil.ph == nil ? nil : SoilEducation.phCaveat
    }

    /// "Nitrogen (N)" reads as "Nitrogen" in a sentence.
    private static func name(of label: String) -> String {
        label.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
    }
}

extension Recommendation.Source {
    /// How the app and the report name where the advice's wording came from.
    var label: String {
        switch self {
        case .foundationModel: return "Written by Apple Intelligence"
        case .rules: return "Standard advice"
        }
    }
}
