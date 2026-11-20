import Foundation

/// Everything the field report PDF says, gathered in one value, so the pages only lay it out and
/// never look anything up or work anything out.
///
/// The advice in it is the exact `Recommendation` on screen, with the same "Based on" line and
/// step labels, passed in by whoever shows the export button. The report never asks for advice of
/// its own and never calls Apple Intelligence, so the PDF cannot say something the app did not.
struct AdviceReport: Sendable {
    /// One kind of organism counted in the sample.
    struct Organism: Sendable, Equatable {
        let name: String
        let count: Int
        /// Counted per kept frame, so a short sweep is not read as poor soil.
        let perFrame: Double
        /// What it is, in plain words. nil for a kind no note covers.
        let about: String?
    }

    /// One earlier or current test of this farm, for the trend page.
    struct HistoryPoint: Sendable, Equatable {
        let date: Date
        /// Organisms counted per kept frame.
        let perFrame: Double
        let moisture: String
        /// True for the test this report is about.
        let isThisSample: Bool
        /// Organisms per frame for each group counted, by display name.
        var byGroup: [String: Double] = [:]
    }

    /// A microscope frame from this sample, read from disk only when the PDF is written.
    struct FrameSource: Sendable, Equatable {
        let url: URL
        let caption: String
    }

    /// A frame's pixels, made small enough for a page, with its caption.
    struct Frame: Sendable {
        let jpeg: Data
        let caption: String
    }

    let farmName: String
    let farmerName: String
    let areaText: String?
    let plotName: String?
    let sampledAt: Date
    let generatedAt: Date
    let moisture: String
    let cropStage: String?
    let recentActions: [String]

    let framesKept: Int
    let totalCount: Int?
    /// The most counted kinds, at most `maximumOrganisms`.
    let organisms: [Organism]
    /// Kinds counted beyond the ones listed.
    let moreKinds: Int

    let levelTitle: String
    let confidence: String
    let reasons: [String]
    let followUp: String

    /// The recorded measurements and fertilizer, with their education. nil when none.
    let education: AdviceEducation?
    let soilUpdatedAt: Date?

    /// Tests of this farm, oldest first, the current one included.
    let history: [HistoryPoint]

    /// At most `maximumFrames`, chosen by position in the sweep.
    let frameSources: [FrameSource]
    /// Filled in by the exporter from `frameSources`. Empty until then.
    var frames: [Frame] = []
    /// False for a report of the soil measurements alone, with no microscope test behind it.
    var hasTest = true

    let recommendation: Recommendation
    /// The "Based on" line shown with the advice. nil when nothing was counted.
    let basis: String?
    /// Why standard advice is shown instead of the model's, if it is, as the app shows it.
    let adviceNote: String?

    /// How many kinds of organism fit on the observation page.
    static let maximumOrganisms = 9
    /// How many microscope frames the report shows.
    static let maximumFrames = 2
    /// Fewer tests than this and no line chart is drawn: two points are a change, not a trend.
    static let minimumPointsForTrend = 3
}

extension AdviceReport {
    var hasTrend: Bool { history.count >= Self.minimumPointsForTrend }

    /// The latest earlier test taken in the same water state as this one, the only fair thing to
    /// compare it with. nil for the first.
    var previousComparable: HistoryPoint? {
        guard let current = history.last(where: \.isThisSample) else { return nil }
        return history.last { $0.date < current.date && $0.moisture == current.moisture }
    }

    static func make(
        farm: Farm, plot: Plot? = nil, test: FarmTest?, recommendation: Recommendation,
        basis: String?, adviceNote: String? = nil, history: [FarmTest] = [],
        generatedAt: Date = Date()
    ) -> AdviceReport {
        // The report is of one plot: its soil and its area. A farm of one plot needs no telling.
        let land = plot ?? farm.plots.first
        let soilOnly = SoilResult.soilOnly(
            land?.soil ?? SoilMeasurements(), recordedAt: land?.soil?.measuredAt ?? generatedAt,
            sampleID: farm.farmerName)
        let result = test?.result ?? soilOnly
        let frames = max(result.framesKept, 1)

        let rows = OrganismTaxonomy.modelClass.rows(from: result.countsByClass ?? [:])
        let organisms = rows.prefix(maximumOrganisms).map { row -> Organism in
            let note = OrganismNotes.note(forLabel: row.label ?? row.name)
            return Organism(
                name: (note?.displayName ?? row.name).translated,
                count: row.count,
                perFrame: Double(row.count) / Double(frames),
                about: note?.plainDescription.translated)
        }

        let plot = result.plotName?.trimmingCharacters(in: .whitespacesAndNewlines)

        // The current test is always in the history, once, whatever was passed.
        var tests = history.filter { $0.id != test?.id }
        if let test { tests.append(test) }
        let points = tests.map { past -> HistoryPoint in
            let pastFrames = Double(max(past.result.framesKept, 1))
            var byGroup: [String: Double] = [:]
            for row in OrganismTaxonomy.modelClass.rows(from: past.result.countsByClass ?? [:]) {
                let name = (OrganismNotes.note(forLabel: row.label ?? row.name)?.displayName ?? row.name)
                    .translated
                byGroup[name, default: 0] += Double(row.count) / pastFrames
            }
            return HistoryPoint(
                date: past.result.recordedAt,
                perFrame: Double(past.result.totalCount ?? 0) / pastFrames,
                moisture: past.result.moisture.label.translated, isThisSample: past.id == test?.id,
                byGroup: byGroup)
        }
        .sorted { $0.date < $1.date }

        var report = AdviceReport(
            farmName: farm.name,
            farmerName: farm.farmerName,
            areaText: land?.areaSquareMetres.map { LandGeometry.areaDescription(squareMetres: $0) },
            plotName: (plot?.isEmpty ?? true) ? nil : plot,
            sampledAt: result.recordedAt,
            generatedAt: generatedAt,
            moisture: result.moisture.label.translated,
            cropStage: result.cropStage?.label.translated,
            recentActions: result.recentActions.map(\.label.translated),
            framesKept: result.framesKept,
            totalCount: result.totalCount,
            organisms: Array(organisms),
            moreKinds: max(rows.count - maximumOrganisms, 0),
            levelTitle: test?.estimate.level.title.translated ?? String(localized: "Soil measurements"),
            confidence: test?.estimate.confidence.label.translated ?? "",
            reasons: test?.estimate.reasons ?? [],
            followUp: test?.estimate.followUp ?? "",
            education: AdviceEducation(land?.soil),
            soilUpdatedAt: (land?.soil?.isEmpty == false) ? land?.soil?.measuredAt : nil,
            history: points,
            frameSources: frameSources(test?.sweep.frameURLs ?? []),
            recommendation: recommendation,
            basis: basis,
            adviceNote: adviceNote)
        report.hasTest = test != nil
        return report
    }

    /// The first frame and the middle one, chosen by where they come in the sweep, not by what is
    /// in them, so the caption never claims more than that.
    static func frameSources(_ urls: [URL]) -> [FrameSource] {
        guard !urls.isEmpty else { return [] }
        var picks = [0]
        if urls.count > 2 { picks.append(urls.count / 2) }
        return picks.prefix(maximumFrames).map { index in
            FrameSource(
                url: urls[index],
                caption: String(
                    localized:
                        "Microscope frame \(index + 1) of \(urls.count) from this sample, chosen by its place in the sweep, not by what it shows."
                )
            )
        }
    }
}
