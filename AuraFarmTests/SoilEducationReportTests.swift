import PDFKit
import SwiftUI
import UIKit
import XCTest

@testable import AuraFarm

/// The soil education, the fertilizer type, the advice built with them, and the field report that
/// carries the same advice as the app.
@MainActor
final class SoilEducationReportTests: XCTestCase {
    // MARK: Helpers

    private let quiet = ["paramecium": 20, "amoeba": 20]

    private func result(
        _ soil: SoilMeasurements?, counts: [String: Int]? = nil, recent: [SampleDetails.RecentAction] = []
    )
        -> SoilResult
    {
        SoilResult(
            sampleID: "A12", recordedAt: Date(timeIntervalSince1970: 1_794_787_200), framesKept: 10,
            moisture: .flooded, countsByClass: counts ?? quiet, sweep: nil, cropStage: nil,
            recentActions: recent,
            stoppedEarly: false, soil: soil)
    }

    private func context(
        _ soil: SoilMeasurements?, counts: [String: Int]? = nil, recent: [SampleDetails.RecentAction] = []
    )
        -> AdviceContext
    {
        let estimate = SoilHealthEstimate(
            level: .good, score: nil, confidence: .low, reasons: [], followUp: "Again.")
        return AdviceContextBuilder().context(
            for: result(soil, counts: counts, recent: recent), estimate: estimate, history: [])
    }

    private final class Unavailable: RecommendationProviding {
        var availability: RecommenderAvailability { .unavailable(reason: "Off in tests.") }
        func prewarm() {}
        func recommend(
            for context: AdviceContext, freshWording: Bool,
            onProgress: @escaping @Sendable (AdviceProgress) -> Void
        ) async throws -> Recommendation {
            XCTFail("The model must not be asked")
            throw CancellationError()
        }
    }

    private func viewModel(_ soil: SoilMeasurements?) -> SoilResultViewModel {
        SoilResultViewModel(
            result: result(soil, counts: ["paramecium": 40, "amoeba": 30, "vorticella": 20]),
            recommender: Unavailable(), historyProvider: { _ in [] }, adviceStore: nil, feedbackStore: nil)
    }

    private func farmAndTest(_ soil: SoilMeasurements?, frames: [URL] = [], date: Date? = nil) -> (
        Farm, FarmTest
    ) {
        let farm = Farm(
            name: "Subak Jatiluwih", farmerName: "Pak Wayan",
            plots: [Plot(corners: [], soil: soil)])
        var testResult = result(soil, counts: ["paramecium": 40, "amoeba": 30, "vorticella": 20])
        if let date { testResult.recordedAt = date }
        let sweep = SavedSweep(
            url: URL(fileURLWithPath: "/tmp/sweep-\(UUID().uuidString)"), manifest: nil,
            recordedAt: testResult.recordedAt, byteCount: 0, frameURLs: frames, panoramaURL: nil)
        let estimate = PlaceholderSoilHealthEstimator().estimate(testResult)
        return (farm, FarmTest(sweep: sweep, result: testResult, estimate: estimate))
    }

    private func pdfText(_ report: AdviceReport) throws -> (pages: Int, text: String) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = try AdvicePDFExporter.write(report, to: directory)
        let document = try XCTUnwrap(PDFDocument(url: url))
        return (document.pageCount, (document.string ?? "").replacingOccurrences(of: "\n", with: " "))
    }

    /// PDFKit breaks lines with spaces or line breaks, so compare without them.
    private func squash(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private let full = SoilMeasurements(
        nitrogen: 100, phosphorus: 20, potassium: 150, ph: 6.5, organicCarbonPercent: 3)

    // MARK: Education

    func testStandardReadingsStillExplainThemselves() {
        for row in full.rows {
            let education = try? XCTUnwrap(row.education, row.label)
            XCTAssertEqual(row.band, .standard, row.label)
            XCTAssertFalse(education?.whatItDoes.isEmpty ?? true, row.label)
            XCTAssertFalse(education?.meaning?.isEmpty ?? true, row.label)
            XCTAssertNil(education?.action, "A standard reading needs no step: \(row.label)")
            XCTAssertFalse(row.note?.action.contains("It's good. Maintain it.") ?? true)
        }
    }

    func testLowHighAndExcessiveReadingsHaveTheirOwnMeanings() {
        let standards: [SoilStandard] = [
            SoilStandards.nitrogen, SoilStandards.phosphorus, SoilStandards.potassium, SoilStandards.ph,
            SoilStandards.organicCarbon,
        ]
        for standard in standards {
            let meanings = [SoilBand.low, .standard, .high, .excessive].compactMap {
                standard.education.detail(for: $0).meaning
            }
            XCTAssertEqual(meanings.count, 4, standard.education.name)
            XCTAssertEqual(
                Set(meanings).count, 4, "Each band says something different: \(standard.education.name)")
            XCTAssertNotNil(standard.education.action[.low], standard.education.name)
            XCTAssertNotNil(standard.education.action[.excessive], standard.education.name)
        }
    }

    func testHighIsReadPerMeasurement() {
        XCTAssertEqual(SoilStandards.potassium.note(for: .high)?.tone, .good)
        XCTAssertEqual(SoilStandards.organicCarbon.note(for: .high)?.tone, .good)
        XCTAssertEqual(SoilStandards.ph.note(for: .high)?.tone, .watch)
        XCTAssertEqual(SoilStandards.nitrogen.note(for: .high)?.tone, .watch)
        // High potassium, nitrogen, pH and carbon ask for no step of their own.
        let high = SoilMeasurements(nitrogen: 130, potassium: 250, ph: 7.4, organicCarbonPercent: 5)
        XCTAssertFalse(context(high).actions.contains(where: \.fromSoil))
    }

    func testEmptyMeasurementsGiveNoEducationAndNoSoilAdvice() {
        XCTAssertNil(AdviceEducation(nil))
        XCTAssertNil(AdviceEducation(SoilMeasurements()))
        XCTAssertFalse(context(SoilMeasurements()).actions.contains(where: \.fromSoil))
    }

    func testPHWordingIsForFloodedRiceAndNeverUniversal() {
        let caveat = SoilEducation.phCaveat
        XCTAssertTrue(
            caveat.contains("A provisional target range for flooded rice soils is around pH 6.0–7.0."))
        XCTAssertTrue(caveat.contains("Flooding can move acidic or alkaline soils toward near-neutral pH"))
        XCTAssertTrue(caveat.contains("air-dried"))
        for word in ["universal", "perfect", "ideal"] {
            XCTAssertFalse(caveat.lowercased().contains(word), word)
        }
        XCTAssertEqual(SoilStandards.ph.lower, 6.0)
        XCTAssertEqual(SoilStandards.ph.upper, 7.0)
        XCTAssertEqual(AdviceEducation(SoilMeasurements(ph: 6.5))?.phCaveat, caveat)
    }

    func testLowPHNeverLeadsToAnAmendment() {
        let wording = [AdviceActions.action(.raisePH)?.wording, AdviceActions.action(.lowerPH)?.wording]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        for amendment in ["lime", "dolomite", "sulfur", "sulphur", "gypsum"] {
            XCTAssertFalse(wording.contains(amendment), amendment)
        }
        XCTAssertTrue(wording.contains("extension officer"))
    }

    func testAPHMeasuredOnDrainedSoilSaysSo() {
        let dry = context(SoilMeasurements(ph: 5.5, phFieldWater: .drained))
        let wet = context(SoilMeasurements(ph: 5.5, phFieldWater: .flooded))
        XCTAssertEqual(dry.actions.first { $0.action.id == .raisePH }?.reason, AdviceReasons.phMeasuredDry)
        XCTAssertEqual(wet.actions.first { $0.action.id == .raisePH }?.reason, AdviceReasons.phLow)
    }

    func testTheEducationAppearsWithTheAdvice() async {
        let model = viewModel(SoilMeasurements(nitrogen: 60, ph: 6.5, fertilizerType: .inorganic))
        await model.loadRecommendation()

        guard case .ready = model.recommendationState else { return XCTFail("\(model.recommendationState)") }
        let education = try? XCTUnwrap(model.education)
        XCTAssertEqual(education?.items.map(\.name), ["Nitrogen", "pH"])
        XCTAssertEqual(education?.items.first?.meaning, SoilEducation.nitrogen.meaning[.low])
        XCTAssertEqual(education?.fertilizer?.label, "Inorganic fertilizer")
        // And the advice itself has the soil step, in the soil group.
        guard case .ready(let shown) = model.recommendationState else { return }
        XCTAssertEqual(shown.steps.first { $0.actionID == .boostNitrogen }?.group, .soil)
    }

    // MARK: Fertilizer

    func testEachFertilizerChoiceIsStoredAndReadBack() throws {
        for type in FertilizerType.allCases {
            let soil = SoilMeasurements(fertilizerType: type)
            let decoded = try JSONDecoder().decode(SoilMeasurements.self, from: JSONEncoder().encode(soil))
            XCTAssertEqual(decoded.fertilizerType, type)
            XCTAssertFalse(decoded.isEmpty, "\(type)")
        }
        XCTAssertEqual(
            FertilizerType.allCases.map(\.label),
            [
                "Organic fertilizer", "Inorganic fertilizer", "Organic–inorganic blend", "Not sure",
                "No fertilizer recorded",
            ])
    }

    func testNoFertilizerRecordedIsNotTheSameAsNeverAsked() {
        let none = SoilMeasurements(fertilizerType: .noneRecorded)
        let never = SoilMeasurements()
        XCTAssertNotEqual(none, never)
        XCTAssertTrue(never.isEmpty)
        XCTAssertNil(never.fertilizerSummary)
        XCTAssertEqual(none.fertilizerSummary, "No fertilizer recorded")
        XCTAssertTrue(FertilizerType.noneRecorded.definition.contains("not proof"))
    }

    func testOlderSavedMeasurementsWithoutTheNewFieldsStillOpen() throws {
        let old = #"{"nitrogen":90,"fertilizerProduct":"Urea","updatedAt":0}"#
        let decoded = try JSONDecoder().decode(SoilMeasurements.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.nitrogen, 90)
        XCTAssertNil(decoded.fertilizerType)
        XCTAssertNil(decoded.phMethod)
    }

    func testFertilizerEducationIsShown() {
        let education = AdviceEducation(SoilMeasurements(fertilizerType: .organic))
        XCTAssertEqual(education?.fertilizer?.education?.contains(FertilizerType.sharedNote), true)
        XCTAssertTrue(
            education?.fertilizer?.education?.hasPrefix("Organic fertilizers can release nutrients gradually")
                ?? false)
        XCTAssertNil(AdviceEducation(SoilMeasurements(fertilizerType: .notSure))?.fertilizer?.education)
        // Neither kind is called better.
        for type in FertilizerType.allCases {
            let text = [type.definition, type.education ?? ""].joined(separator: " ").lowercased()
            XCTAssertFalse(text.contains("better"), "\(type)")
        }
    }

    func testOnlyInorganicFertilizerAloneCreatesAdvice() {
        let plain = context(nil).actions
        for type in FertilizerType.allCases {
            let actions = context(SoilMeasurements(fertilizerType: type)).actions
            if type == .inorganic {
                XCTAssertEqual(actions.filter(\.fromSoil).map(\.action.id), [.addOrganicInput])
            } else {
                XCTAssertEqual(actions, plain, "\(type)")
            }
            // Beside a standard reading, only the inorganic one adds a step.
            XCTAssertEqual(
                context(SoilMeasurements(nitrogen: 100, fertilizerType: type)).actions.contains(
                    where: \.fromSoil),
                type == .inorganic, "\(type)")
        }
    }

    func testFertilizerAmountsAndProductsNeverReachTheModel() {
        let soil = SoilMeasurements(
            nitrogen: 60, fertilizerType: .inorganic, fertilizerProduct: "Brandname Gold",
            fertilizerKilogramsPerHectare: 250)
        let prompt = AdvicePromptBuilder.prompt(for: context(soil))

        XCTAssertFalse(prompt.contains("250"))
        XCTAssertFalse(prompt.contains("kg/ha"))
        XCTAssertFalse(prompt.contains("Brandname"))
        XCTAssertTrue(
            prompt.contains("Fertilizer kind recorded (background only, not advice): inorganic fertilizer."))
        XCTAssertTrue(
            AdvicePromptBuilder.instructions().contains("Do not judge it, and do not suggest a fertilizer"))
    }

    func testTheKindAloneIsNotSentWithoutAReading() {
        XCTAssertNil(SoilInputs(SoilMeasurements(fertilizerType: .organic)))
        XCTAssertNil(SoilInputs(SoilMeasurements(ph: 6.5, fertilizerType: .notSure))?.fertilizerType)
    }

    func testRecentFertilizingStillShapesTheMicroscopeAdvice() {
        let counts = ["euglena": 40, "phacus": 20, "paramecium": 2]
        let withType = context(
            SoilMeasurements(nitrogen: 100, fertilizerType: .organic), counts: counts, recent: [.fertilized])
        XCTAssertEqual(
            withType.actions.first { $0.action.id == .reviewFertilizer }?.reason,
            AdviceReasons.fertilizerAfterFertilizing)
    }

    func testChangingTheFertilizerTypeIsANewAdviceInput() {
        let organic = SoilInputs(SoilMeasurements(nitrogen: 60, fertilizerType: .organic))
        let inorganic = SoilInputs(SoilMeasurements(nitrogen: 60, fertilizerType: .inorganic))
        XCTAssertNotEqual(organic, inorganic)
        XCTAssertEqual(
            AdviceUpdateNote.text(from: organic, to: inorganic), "Updated with the new fertilizer type.")
    }

    // MARK: Combined advice

    func testStandardAdviceWithMeasurementsKeepsBothSources() async {
        let model = viewModel(SoilMeasurements(nitrogen: 60, organicCarbonPercent: 1.5))
        await model.loadRecommendation()
        guard case .ready(let shown) = model.recommendationState else { return XCTFail() }

        XCTAssertEqual(shown.source, .rules)
        XCTAssertTrue(shown.summary.contains("The soil measurements point to a few changes too."))
        let soilSteps = model.adviceContext?.actions.filter(\.fromSoil).map(\.action.id) ?? []
        XCTAssertFalse(soilSteps.isEmpty)
        XCTAssertTrue(shown.steps.contains { $0.actionID.map(soilSteps.contains) ?? false })
    }

    func testAStepBothSidesCallForIsOneStepMarkedAsAlsoFromSoil() {
        let low = context(SoilMeasurements(organicCarbonPercent: 1.5), counts: ["paramecium": 2])
        let compost = low.actions.filter { $0.action.id == .addCompost }
        XCTAssertEqual(compost.count, 1)
        XCTAssertEqual(compost.first?.fromSoil, true)
        XCTAssertEqual(compost.first?.fromMicroscope, true)
    }

    func testTheNewNeverSayRulesCatchDiagnosisAndAlwaysClaims() {
        let ctx = context(nil)
        for text in [
            "This reading is a diagnosis.", "More carbon is always better.", "High pH is always bad.",
        ] {
            XCTAssertFalse(AdviceOutputChecker.problems(in: text, context: ctx, wordLimit: 40).isEmpty, text)
        }
    }

    // MARK: The report

    func testAReportWithoutMeasurementsExports() throws {
        let (farm, test) = farmAndTest(nil)
        let report = AdviceReport.make(
            farm: farm, test: test, recommendation: AdviceReport.sample().recommendation,
            basis: "Based on it.")
        let (pages, text) = try pdfText(report)

        XCTAssertEqual(pages, AdviceReportPages.titles(for: report).count)
        XCTAssertTrue(
            squash(text).contains(squash("No soil measurements or fertilizer information have been recorded"))
        )
        XCTAssertEqual(
            AdviceReportPages.titles(for: report),
            ["Field summary", "What to do next", "Notes and limitations"])
        XCTAssertTrue(squash(text).contains(squash("More samples are needed before a trend can be shown.")))
    }

    func testAReportWithMeasurementsCarriesValuesBandsEducationAndAdvice() throws {
        let report = AdviceReport.sample()
        let (pages, text) = try pdfText(report)
        let flat = squash(text)

        XCTAssertEqual(pages, AdviceReportPages.titles(for: report).count)
        for needle in [
            "60 mg/kg", "Low", 5.6.formatted(.number.precision(.fractionLength(0...2))),
            "Organic fertilizer", "Compost", "500 kg/ha", SoilEducation.phCaveat,
            report.basis!, report.recommendation.summary, "Microscope test",
            "Soil measurements", "Things you can do now", "After harvest", "Before acting",
            "not a diagnosis",
        ] {
            XCTAssertTrue(flat.lowercased().contains(squash(needle).lowercased()), needle)
        }
    }

    func testTheReportsAdviceIsTheOneOnScreen() async throws {
        let soil = SoilMeasurements(nitrogen: 60, ph: 8.2, fertilizerType: .blend)
        let model = viewModel(soil)
        await model.loadRecommendation()
        guard case .ready(let shown) = model.recommendationState else { return XCTFail() }

        let (farm, test) = farmAndTest(soil)
        let report = AdviceReport.make(
            farm: farm, test: test, recommendation: shown, basis: model.adviceBasis,
            adviceNote: model.modelUnavailableReason)

        XCTAssertEqual(report.recommendation, shown)
        XCTAssertEqual(report.basis, model.adviceBasis)
        XCTAssertEqual(report.education, model.education)
        let flat = squash(try pdfText(report).text)
        for step in shown.steps {
            XCTAssertTrue(flat.contains(squash(step.text)), step.text)
            if let why = step.why { XCTAssertTrue(flat.contains(squash(why)), why) }
            if let timing = step.timing { XCTAssertTrue(flat.contains(squash(timing)), timing) }
        }
        XCTAssertTrue(flat.contains(squash(shown.source.label)))
        // Both groups are on screen and in the report.
        XCTAssertTrue(shown.steps.contains { $0.group == .microscope })
        XCTAssertTrue(shown.steps.contains { $0.group == .soil })
    }

    func testChangedMeasurementsChangeTheAdviceInTheNextReport() async throws {
        let before = viewModel(SoilMeasurements(nitrogen: 100))
        await before.loadRecommendation()
        let after = viewModel(SoilMeasurements(nitrogen: 200))
        await after.loadRecommendation()
        guard case .ready(let first) = before.recommendationState,
            case .ready(let second) = after.recommendationState
        else { return XCTFail() }

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.steps.contains { $0.actionID == .reduceNitrogen })
        let (farm, test) = farmAndTest(SoilMeasurements(nitrogen: 200))
        let text = try pdfText(AdviceReport.make(farm: farm, test: test, recommendation: second, basis: nil))
            .text
        XCTAssertTrue(squash(text).contains(squash(AdviceActions.action(.reduceNitrogen)!.wording)))
        XCTAssertTrue(text.contains("Excessive"))
    }

    func testChangingTheFertilizerUpdatesTheReport() throws {
        let (farm, test) = farmAndTest(SoilMeasurements(fertilizerType: .organic))
        var changed = farm
        changed.plots[0].soilLog = [SoilMeasurements(fertilizerType: .inorganic)]
        let recommendation = AdviceReport.sample().recommendation
        let first = try pdfText(
            AdviceReport.make(farm: farm, test: test, recommendation: recommendation, basis: nil))
        let second = try pdfText(
            AdviceReport.make(farm: changed, test: test, recommendation: recommendation, basis: nil))
        XCTAssertTrue(first.text.contains("Organic fertilizer"))
        XCTAssertTrue(second.text.contains("Inorganic fertilizer"))
        XCTAssertFalse(second.text.contains("Organic fertilizer"))
    }

    func testStepsAreSplitByWhenTheyCanBeDone() {
        typealias When = AdviceReportPages.When
        XCTAssertEqual(When(timing: "Now"), .now)
        XCTAssertEqual(When(timing: "2 to 4 weeks"), .now)
        XCTAssertEqual(When(timing: nil), .now)
        XCTAssertEqual(When(timing: "After harvest"), .afterHarvest)
        XCTAssertEqual(When(timing: "Next fallow"), .afterHarvest)
        XCTAssertEqual(When(timing: "Before acting"), .beforeActing)
        XCTAssertEqual(When(timing: "Before next application"), .beforeActing)
    }

    func testATrendNeedsEnoughTests() throws {
        let date = Date(timeIntervalSince1970: 1_794_787_200)
        let one = AdviceReport.sample()
        XCTAssertFalse(one.hasTrend)
        XCTAssertTrue(try pdfText(one).text.contains("More samples are needed"))

        var points: [AdviceReport.HistoryPoint] = []
        for index in 0..<4 {
            let when = date.addingTimeInterval(Double(index) * 1_209_600)
            let moisture = index == 2 ? "Drained" : "Flooded"
            points.append(
                AdviceReport.HistoryPoint(
                    date: when, perFrame: Double(2 + index), moisture: moisture, isThisSample: index == 3,
                    byGroup: ["Ciliates": Double(1 + index), "Rotifers": 1]))
        }
        let many = AdviceReport.sample(history: points)
        XCTAssertTrue(many.hasTrend)
        let text = try pdfText(many).text
        XCTAssertTrue(text.contains("Organisms per frame"))
        XCTAssertTrue(text.contains("association"))
    }

    func testTheReportsHistoryHoldsTheCurrentTestOnce() {
        let (farm, test) = farmAndTest(nil)
        let (_, older) = farmAndTest(nil, date: Date(timeIntervalSince1970: 1_790_000_000))
        let report = AdviceReport.make(
            farm: farm, test: test, recommendation: AdviceReport.sample().recommendation, basis: nil,
            history: [test, older])
        XCTAssertEqual(report.history.count, 2)
        XCTAssertEqual(report.history.filter(\.isThisSample).count, 1)
        XCTAssertEqual(report.history.last?.isThisSample, true)
    }

    func testMicroscopeFramesAreDrawnWithCaptions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try (0..<5).map { index -> URL in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { context in
                UIColor(white: 0.2 + Double(index) * 0.1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            }
            let url = directory.appending(path: "frame\(index).jpg")
            try XCTUnwrap(image.jpegData(compressionQuality: 0.8)).write(to: url)
            return url
        }
        let (farm, test) = farmAndTest(SoilMeasurements(ph: 6.5), frames: urls)
        let report = AdviceReport.make(
            farm: farm, test: test, recommendation: AdviceReport.sample().recommendation, basis: nil)

        XCTAssertEqual(report.frameSources.map(\.url), [urls[0], urls[2]])
        XCTAssertEqual(AdvicePDFExporter.withFrames(report).frames.count, 2)
        let text = try pdfText(report).text
        XCTAssertTrue(squash(text).contains(squash("Microscope frame 1 of 5 from this sample")))

        // A frame that cannot be read is left out, never replaced by a placeholder.
        let missing = AdviceReport.make(
            farm: farm, test: farmAndTest(nil, frames: [directory.appending(path: "gone.jpg")]).1,
            recommendation: AdviceReport.sample().recommendation, basis: nil)
        XCTAssertTrue(AdvicePDFExporter.withFrames(missing).frames.isEmpty)
    }

    /// Writes every page of a few reports as PNG files, for looking at by eye. The folder is printed.
    func testRenderPagesForVisualCheck() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ReportPages")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_794_787_200)
        let values: [Double] = [2.1, 3.4, 2.8, 3.6]
        var points: [AdviceReport.HistoryPoint] = []
        for index in 0..<4 {
            let when = date.addingTimeInterval(Double(index) * 1_209_600)
            let moisture = index == 2 ? "Drained" : "Flooded"
            let groups: [String: Double] = [
                "Ciliates": values[index] * 0.65, "Rotifers": values[index] * 0.25,
                "Nematodes": values[index] * 0.10,
            ]
            points.append(
                AdviceReport.HistoryPoint(
                    date: when, perFrame: values[index], moisture: moisture, isThisSample: index == 3,
                    byGroup: groups))
        }
        var withFrame = AdviceReport.sample(history: points, steps: 5)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { context in
            UIColor(red: 0.55, green: 0.6, blue: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        withFrame.frames = [
            AdviceReport.Frame(
                jpeg: image.jpegData(compressionQuality: 0.8)!,
                caption:
                    "Microscope frame 1 of 12 from this sample, chosen by its place in the sweep, not by what it shows."
            )
        ]
        let reports: [(String, AdviceReport)] = [
            ("empty", AdviceReport.sample(soil: nil, steps: 2)),
            ("single", AdviceReport.sample(steps: 5)),
            ("full", withFrame),
            ("long", AdviceReport.sample(history: points, steps: 9)),
        ]
        for (name, report) in reports {
            for (index, page) in AdviceReportPages.pages(for: report).enumerated() {
                let renderer = ImageRenderer(content: page)
                renderer.scale = 2
                let data = try XCTUnwrap(renderer.uiImage?.pngData())
                try data.write(to: folder.appending(path: "\(name)-\(index + 1).png"))
            }
        }
        print("REPORT_PAGES_FOLDER=\(folder.path)")
    }

    func testWritingAReportChangesNoFarmData() throws {
        let store = FarmStore(fileURL: nil, farms: [farmAndTest(SoilMeasurements(ph: 6.5)).0])
        let before = store.farms
        let (farm, test) = farmAndTest(SoilMeasurements(ph: 6.5))
        _ = try pdfText(
            AdviceReport.make(
                farm: farm, test: test, recommendation: AdviceReport.sample().recommendation, basis: nil))
        XCTAssertEqual(store.farms, before)
    }
}
