import Charts
import SwiftUI

/// The pages of the field report PDF, as SwiftUI views the size of an A4 sheet.
///
/// Three pages: the field summary (who, when, what the microscope saw and the soil measurements),
/// what to do next (every step in one table, split by when it can be done), and the notes and
/// limitations. Each page has a fixed size and does not scroll, and no text goes below 7 points.
///
/// Every word of advice comes from the report value, which carries the recommendation shown in
/// the app, steps and groups included. Nothing here writes or changes advice.
enum AdviceReportPages {
    static let titles = ["Field summary", "What to do next", "Notes and limitations"]

    static func titles(for report: AdviceReport) -> [String] { titles }

    static func pages(for report: AdviceReport) -> [AnyView] {
        let total = titles.count
        return [
            AnyView(
                ReportPage(report: report, section: titles[0], number: 1, total: total) {
                    SummaryPage(report: report)
                }),
            AnyView(
                ReportPage(report: report, section: titles[1], number: 2, total: total) {
                    NextStepsPage(report: report)
                }),
            AnyView(
                ReportPage(report: report, section: titles[2], number: 3, total: total) {
                    NotesPage(report: report)
                }),
        ]
    }

    /// When a step can be done, in the three groups the "What to do next" page is split into.
    enum When: CaseIterable {
        case now, afterHarvest, beforeActing

        var title: String {
            switch self {
            case .now: "Things you can do now"
            case .afterHarvest: "After harvest"
            case .beforeActing: "Before acting"
            }
        }

        /// "Before ..." timings are things to check or prepare first, "After harvest" and the
        /// fallow are for once the crop is off, and everything else can be started now.
        init(timing: String?) {
            let text = (timing ?? "").lowercased()
            if text.hasPrefix("before") {
                self = .beforeActing
            } else if text.hasPrefix("after harvest") || text == "next fallow" {
                self = .afterHarvest
            } else {
                self = .now
            }
        }
    }
}

// MARK: - Look

private enum Style {
    // The app's own colours: the black and lime of the logo for the band, the olive of the lime
    // darkened so it reads on paper for the accents, and a warm cream for the panels. The status
    // colours stay muted so they read like a second ink.
    static let paper = Color.white
    static let band = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let lime = Color.auraGreen
    static let ink = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let muted = Color(red: 0.38, green: 0.38, blue: 0.36)
    static let accent = Color(red: 0.36, green: 0.43, blue: 0)
    static let good = Color(red: 0.14, green: 0.38, blue: 0.31)
    static let amber = Color(red: 0.62, green: 0.43, blue: 0.06)
    static let rust = Color(red: 0.55, green: 0.15, blue: 0.18)
    static let line = Color(red: 0.80, green: 0.79, blue: 0.74)
    static let panel = Color(red: 0.965, green: 0.95, blue: 0.90)
    static let slate = Color(red: 0.40, green: 0.56, blue: 0.66)

    /// One colour for each organism group, in a fixed order.
    static let groups: [Color] = [slate, accent, Color.auraBrown, amber, muted]

    static func color(for tone: SoilTone?) -> Color {
        switch tone {
        case .good: return good
        case .watch: return amber
        case .act: return rust
        case nil: return muted
        }
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    /// For readings and figures, set like the numbers on a printed form.
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func body(_ size: CGFloat = 9.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

private func day(_ date: Date) -> String {
    date.formatted(date: .long, time: .omitted)
}

private func shortDay(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
}

private func perFrame(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
}

/// The groups across the tests, most counted first, at most five. They are the chart's lines and
/// the legend beside it, in the same order so the colours agree.
private func groupNames(_ report: AdviceReport) -> [String] {
    var totals: [String: Double] = [:]
    for point in report.history {
        for (name, value) in point.byGroup { totals[name, default: 0] += value }
    }
    if totals.isEmpty { return report.organisms.prefix(5).map(\.name) }
    return totals.sorted { $0.value > $1.value }.prefix(5).map(\.key)
}

// MARK: - The sheet every page sits on

private struct ReportPage<Content: View>: View {
    let report: AdviceReport
    let section: String
    let number: Int
    let total: Int
    let content: Content

    init(
        report: AdviceReport, section: String, number: Int, total: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.report = report
        self.section = section
        self.number = number
        self.total = total
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("Icon_PDF")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
                Text("TERRALOKA")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(2.7)
                    .foregroundStyle(Style.lime)
                Spacer()
                Text("\(section) · \(number)/\(total)")
                    .font(Style.mono(8, weight: .regular))
                    .foregroundStyle(Style.lime.opacity(0.8))
            }
            .padding(.horizontal, 24)
            .frame(width: 595, height: 65)
            .background(Style.band)

            content
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer(minLength: 6)

            Rectangle().fill(Style.line).frame(height: 0.5).padding(.horizontal, 24)
            Text(
                "For monitoring and learning, not a diagnosis. Standards are provisional and not yet reviewed by an agronomist. Ask an extension officer before making a major change."
            )
            .font(Style.body(7.5))
            .foregroundStyle(Style.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Style.paper)
        .foregroundStyle(Style.ink)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Small parts

private func heading(_ text: String) -> some View {
    Text(text).font(Style.title(20))
}

private func smallCaps(_ text: String) -> some View {
    Text(text)
        .font(Style.body(9.5, weight: .bold))
        .foregroundStyle(Style.accent)
}

private func labelled(_ label: String, _ text: String, size: CGFloat = 8.5) -> some View {
    (Text(label + "  ").font(Style.body(size, weight: .semibold)).foregroundColor(Style.muted)
        + Text(text).font(Style.body(size)))
        .fixedSize(horizontal: false, vertical: true)
}

private func chip(_ text: String, color: Color) -> some View {
    Text(text)
        .font(Style.body(7.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(color, lineWidth: 0.8))
}

private struct Card<Content: View>: View {
    var fill: Color = .white
    var stroke: Color = Style.line
    let content: Content

    init(fill: Color = .white, stroke: Color = Style.line, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.stroke = stroke
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(stroke, lineWidth: 0.6))
    }
}

private struct FrameImage: View {
    let frame: AdviceReport.Frame
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let image = UIImage(data: frame.jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .overlay(Rectangle().stroke(Style.line, lineWidth: 0.5))
            }
            Text(frame.caption)
                .font(Style.body(7.5))
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 1: field summary

private struct SummaryPage: View {
    let report: AdviceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Field Summary").font(Style.title(28))
                Text(report.recommendation.summary)
                    .font(Style.body(12))
                    .fixedSize(horizontal: false, vertical: true)
            }

            details

            if report.hasTest { microscope }
            soilMeasurements
        }
    }

    // MARK: Details

    private var details: some View {
        let plot = report.plotName ?? "None named"
        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                detail("Farmer", report.farmerName)
                detail("Plot", plot, sub: report.areaText)
                detail("Farm", report.farmName)
            }
            HStack(alignment: .top, spacing: 0) {
                detail("Sampled Date", day(report.sampledAt))
                detail("Report Date", day(report.generatedAt))
                detail("Water state", [report.moisture, report.cropStage].compactMap { $0 }.joined(separator: " · "))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Style.panel.opacity(0.5))
        .overlay(alignment: .leading) { Rectangle().fill(Style.accent.opacity(0.7)).frame(width: 5) }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Style.accent.opacity(0.32), lineWidth: 0.6))
    }

    private func detail(_ label: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Style.body(11))
            Text(value).font(Style.body(11, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).font(Style.body(8)).foregroundStyle(Style.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Microscope

    private var microscope: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Microscopic Interpretation")
            Text(interpretation)
                .font(Style.body(11))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 18) {
                chart.frame(width: 350)
                presence
            }
        }
    }

    private var interpretation: String {
        var parts: [String] = []
        if let total = report.totalCount {
            parts.append(
                "\(total == 1 ? "1 organism was" : "\(total) organisms were") counted across \(report.framesKept) frames.")
        }
        parts.append(contentsOf: report.reasons.filter { !$0.localizedCaseInsensitiveContains("counted") })
        if !report.confidence.isEmpty { parts.append("\(report.levelTitle), with \(report.confidence.lowercased()) confidence.") }
        if let previous = report.previousComparable {
            parts.append(
                "The current sample was compared with the sample of \(day(previous.date)), taken in the same water state."
            )
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Soil life over time").font(Style.title(16))
            if report.history.count >= 2 {
                TrendChart(report: report, names: groupNames(report), height: 105)
            }
            Text(
                report.hasTrend
                    ? "Each point is one test, counted per microscope frame. A change over time is an association only: this chart does not show what caused it. Counts from flooded and drained fields are not directly comparable."
                    : "More samples are needed before a trend can be shown. The more tests you take over time, the clearer the picture of your soil life becomes. Counts are per microscope frame, and flooded and drained fields are not directly comparable."
            )
            .font(Style.body(8))
            .foregroundStyle(Style.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presence: some View {
        let names = groupNames(report)
        return VStack(alignment: .leading, spacing: 7) {
            Text("Soil life presence").font(Style.title(16))
            if report.organisms.isEmpty {
                Text("Nothing was counted in this sample.")
                    .font(Style.body(9))
                    .foregroundStyle(Style.muted)
            }
            ForEach(names.indices, id: \.self) { index in
                let organism = report.organisms.first { $0.name == names[index] }
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(Style.groups[index % Style.groups.count]).frame(width: 12, height: 12)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(names[index]).font(Style.body(11))
                        if let organism {
                            Text("\(organism.count) found · \(perFrame(organism.perFrame)) per frame")
                                .font(Style.mono(7.5, weight: .regular))
                                .foregroundStyle(Style.accent)
                            // With many groups the descriptions would push the page past its end.
                            if names.count <= 3, let about = organism.about {
                                Text(about)
                                    .font(Style.body(8))
                                    .foregroundStyle(Style.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if report.moreKinds > 0 {
                Text("Also counted: \(report.moreKinds) more kinds.")
                    .font(Style.body(8))
                    .foregroundStyle(Style.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Soil measurements

    private let slots = ["Nitrogen", "Phosphorus", "Potassium", "pH", "Organic carbon"]

    @ViewBuilder
    private var soilMeasurements: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Your soil measurements")
            if report.education == nil {
                Text(
                    "No soil measurements or fertilizer information have been recorded for this farm. Adding nitrogen, phosphorus, potassium, pH, organic carbon and the fertilizer type on the farm's page shows where each sits against its standard, and adds soil steps to the advice."
                )
                .font(Style.body(10))
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(intro)
                    .font(Style.body(11))
                    .fixedSize(horizontal: false, vertical: true)
                let cells = slots.map { name in
                    AnyView(
                        report.education?.items.first(where: { $0.name == name }).map {
                            AnyView(measurementCard($0))
                        } ?? AnyView(missingCard(name)))
                } + [AnyView(fertilizerCard)]
                ForEach(0..<2, id: \.self) { row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(0..<3, id: \.self) { column in cells[row * 3 + column] }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var intro: String {
        var text =
            "Recorded by the field helper, separately from the microscope. Each reading is placed against provisional standards for flooded rice, not graded."
        if let updated = report.soilUpdatedAt { text += " Updated \(shortDay(updated))." }
        return text
    }

    private func measurementCard(_ item: AdviceEducation.Item) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.name).font(Style.body(9, weight: .semibold))
                    Spacer(minLength: 0)
                    chip(item.band, color: Style.color(for: item.tone))
                }
                Text(item.value).font(Style.mono(15))
                RangeBar(standard: item.standard, value: item.number)
                if let context = item.context {
                    Text(context).font(Style.body(7)).foregroundStyle(Style.muted)
                }
            }
        }
    }

    private func missingCard(_ name: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(Style.body(9, weight: .semibold)).foregroundStyle(Style.muted)
                Text("Not recorded").font(Style.title(13)).foregroundStyle(Style.muted)
                Text("No reading was entered, so nothing is shown or assumed.")
                    .font(Style.body(7.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fertilizerCard: some View {
        Card(fill: Style.panel, stroke: .clear) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fertilizer").font(Style.body(9, weight: .semibold))
                if let fertilizer = report.education?.fertilizer {
                    Text(fertilizer.label).font(Style.title(13))
                    if let verdict = fertilizer.verdict {
                        chip(verdict, color: Style.color(for: fertilizer.tone))
                    }
                    if let details = fertilizer.details {
                        labelled("Recorded", details, size: 7.5)
                    }
                } else {
                    Text("Not recorded").font(Style.title(13)).foregroundStyle(Style.muted)
                    Text("No fertilizer type was chosen. Nothing is assumed about what was used.")
                        .font(Style.body(7.5))
                        .foregroundStyle(Style.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Where a reading sits across the four bands of its standard. The limits are the provisional
/// ones from `SoilStandards`, and the marker is the recorded value.
private struct RangeBar: View {
    let standard: SoilStandard
    let value: Double

    private var domain: ClosedRange<Double> {
        let isPH = standard.lower >= 5 && standard.upper <= 8
        let low = isPH ? 4.0 : 0.0
        let top = standard.highUpper ?? standard.upper
        let high = max(top * 1.3, value * 1.05, low + 1)
        return low...high
    }

    private func fraction(_ x: Double) -> CGFloat {
        let d = domain
        return CGFloat(min(max((x - d.lowerBound) / (d.upperBound - d.lowerBound), 0), 1))
    }

    var body: some View {
        let top = standard.highUpper ?? standard.upper
        let edges: [Double] = [domain.lowerBound, standard.lower, standard.upper, top, domain.upperBound]
        let colors: [Color] = [
            Style.amber.opacity(0.55), Style.good, Style.muted.opacity(0.45), Style.rust.opacity(0.75),
        ]
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        ForEach(0..<4, id: \.self) { index in
                            let share = fraction(edges[index + 1]) - fraction(edges[index])
                            Rectangle()
                                .fill(colors[index])
                                .frame(width: max(proxy.size.width * share - 1, 1))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 6)
                    Rectangle()
                        .fill(Style.ink)
                        .frame(width: 2, height: 14)
                        .offset(x: proxy.size.width * fraction(value) - 1)
                }
            }
            .frame(height: 14)
            HStack {
                Text("Low")
                Spacer()
                Text("Standard")
                Spacer()
                Text("High")
                Spacer()
                Text("Excessive")
            }
            .font(Style.body(7))
            .foregroundStyle(Style.muted)
        }
    }
}

// MARK: - Page 2: what to do next

private struct NextStepsPage: View {
    let report: AdviceReport

    private var steps: [(number: Int, step: Recommendation.Step)] {
        Array(report.recommendation.steps.enumerated()).map { ($0.offset + 1, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("What to do next").font(Style.title(28))
                Text(report.recommendation.summary)
                    .font(Style.body(12))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceLine)
                    .font(Style.body(8.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text("No.").frame(width: 18, alignment: .leading)
                    Text("Step").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Why").frame(width: 170, alignment: .leading)
                    Text("Where it is from").frame(width: 84, alignment: .leading)
                }
                .font(Style.body(8, weight: .bold))
                .foregroundStyle(Style.muted)
                .padding(.bottom, 4)

                ForEach(AdviceReportPages.When.allCases, id: \.self) { when in
                    let rows = steps.filter { AdviceReportPages.When(timing: $0.step.timing) == when }
                    if !rows.isEmpty {
                        Rectangle().fill(Style.line).frame(height: 0.5)
                        HStack {
                            Text(when.title)
                            Spacer()
                            Text("\(rows.count)")
                        }
                        .font(Style.body(10, weight: .bold))
                        .foregroundStyle(Style.accent)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 5)
                        .background(Style.panel)
                        ForEach(rows, id: \.number) { row in
                            Rectangle().fill(Style.line).frame(height: 0.5)
                            stepRow(row.step, number: row.number)
                        }
                    }
                }
                Rectangle().fill(Style.line).frame(height: 0.5)
            }

            if let basis = report.basis {
                Text(basis)
                    .font(Style.body(8.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceLine: String {
        var text = report.recommendation.source.label + "."
        if let note = report.adviceNote { text += " " + note }
        return text
    }

    private func origin(_ step: Recommendation.Step) -> String {
        switch step.group {
        case .microscope: step.alsoFromSoil ? "Microscope test, and soil measurements" : "Microscope test"
        case .soil: "Soil measurements"
        case nil: ""
        }
    }

    private func stepRow(_ step: Recommendation.Step, number: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%02d", number))
                .font(Style.mono(9))
                .foregroundStyle(Style.accent)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.text)
                    .font(Style.body(11, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let timing = step.timing {
                    Text(timing)
                        .font(Style.body(8.5, weight: .medium))
                        .foregroundStyle(Style.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(step.why ?? "")
                .font(Style.body(9.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 170, alignment: .leading)
            Text(origin(step))
                .font(Style.body(9.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 84, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }
}

// MARK: - Page 3: notes and limitations

private struct NotesPage: View {
    let report: AdviceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Notes and limitations").font(Style.title(28))
            if !report.frames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    smallCaps("From the microscope")
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(report.frames.indices, id: \.self) { index in
                            FrameImage(frame: report.frames[index], height: 170)
                        }
                    }
                }
            }
            if report.hasTest { CanCannotBox() }
            NotesBlock(report: report)
        }
    }
}

private struct CanCannotBox: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("What the microscope can show")
                    .font(Style.body(9.5, weight: .semibold))
                    .foregroundStyle(Style.accent)
                Text(
                    "How many small organisms of each group live in a drop of soil water, counted per frame, and whether that changes between samples taken in the same water state."
                )
                .font(Style.body(10))
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 3) {
                Text("What it can't show")
                    .font(Style.body(9.5, weight: .semibold))
                    .foregroundStyle(Style.rust)
                Text(
                    "Nutrient levels, pH, organic carbon, or which nematodes are pests. Those need the field helper's soil measurements or a laboratory test. It is not a laboratory soil test."
                )
                .font(Style.body(10))
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Style.panel)
    }
}

private struct NotesBlock: View {
    let report: AdviceReport

    private var phLine: String {
        guard let ph = report.education?.items.first(where: { $0.name == "pH" }) else {
            return "No pH was recorded for this farm."
        }
        if let context = ph.context { return "This farm's pH reading: \(context)." }
        return "How and when this farm's pH was measured was not recorded, so read it with care."
    }

    private var madeLine: String {
        var text =
            "The app's fixed rules chose every step from the microscope test and the soil measurements. "
        text +=
            report.recommendation.source == .foundationModel
            ? "Apple Intelligence on the phone only wrote the wording, which was checked first. "
            : "The wording is the app's standard advice. "
        return text + "This report shows the advice the app showed on \(day(report.generatedAt))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            note(
                "Standards",
                "A provisional first draft for flooded rice paddies. No agronomist has reviewed it yet.")
            note("pH in flooded rice", SoilEducation.phCaveat + " " + phLine)
            note(
                "Measurements",
                "Probe and laboratory readings can differ, and a reading depends on where, how deep and when the soil was sampled. Only the latest measurements are kept, so no soil trend can be shown."
            )
            note(
                "Fertilizer",
                "The type is what the field helper chose from a list. “No fertilizer recorded” does not mean none was used, and “Not sure” is never guessed at. No step gives a product, an amount or a rate."
            )
            note(
                "Using this report",
                "For monitoring and learning, not a diagnosis. Ask an extension officer before making a major change."
            )
            note("How the advice was made", madeLine)
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Style.body(10.5, weight: .semibold)).foregroundStyle(Style.accent)
            Text(text).font(Style.body(10)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrendChart: View {
    let report: AdviceReport
    let names: [String]
    let height: CGFloat

    var body: some View {
        Chart {
            ForEach(names, id: \.self) { name in
                ForEach(report.history.indices, id: \.self) { index in
                    let point = report.history[index]
                    let value = point.byGroup[name] ?? 0
                    LineMark(
                        x: .value("Sample date", point.date),
                        y: .value("Organisms per frame", value),
                        series: .value("Group", name)
                    )
                    .foregroundStyle(by: .value("Group", name))
                    PointMark(
                        x: .value("Sample date", point.date),
                        y: .value("Organisms per frame", value)
                    )
                    .foregroundStyle(by: .value("Group", name))
                }
            }
        }
        .chartForegroundStyleScale(
            domain: names, range: Array(Style.groups.prefix(max(names.count, 1)))
        )
        .chartXScale(range: .plotDimension(padding: 22))
        .chartYAxisLabel("Organisms per frame")
        .chartXAxis {
            AxisMarks(values: report.history.map(\.date)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
    }
}

// MARK: - Preview and sample data

#if DEBUG
    extension AdviceReport {
        /// Made-up data, to look at the pages in Xcode's canvas and in tests without a real test.
        static func sample(
            soil: SoilMeasurements? = SoilMeasurements(
                nitrogen: 60, phosphorus: 20, potassium: 200, ph: 5.6, organicCarbonPercent: 1.6,
                phMethod: .fieldProbe, phFieldWater: .drained, fertilizerType: .organic,
                fertilizerProduct: "Compost", fertilizerKilogramsPerHectare: 500),
            history: [HistoryPoint] = [],
            steps: Int = 5
        ) -> AdviceReport {
            let now = Date(timeIntervalSince1970: 1_794_787_200)
            func step(
                _ id: AdviceAction.ID, _ text: String, _ why: String?, _ timing: String?,
                _ group: Recommendation.Step.Group, also: Bool = false
            ) -> Recommendation.Step {
                var step = Recommendation.Step(actionID: id, text: text, why: why, timing: timing)
                step.group = group
                step.alsoFromSoil = also
                return step
            }
            let all: [Recommendation.Step] = [
                step(
                    .addCompost, "Add well-rotted compost or manure if you have it.",
                    "Organic carbon is low, and compost builds it up.", "Before planting", .microscope,
                    also: true),
                step(
                    .resampleLater, "Test this plot again in a few weeks.",
                    "One test is a snapshot, and a second shows the direction.", "In 2 to 4 weeks",
                    .microscope),
                step(
                    .keepNotes,
                    "Write down what you did in this field, so the next sample can be compared fairly.",
                    "Notes make the next sample easier to read.", "Now", .microscope),
                step(
                    .boostNitrogen,
                    "Between seasons, grow beans as a cover crop to keep living roots in the soil and add nitrogen.",
                    "Nitrogen in the soil is low, and plants need it for leaves and stems.", "Next fallow",
                    .soil),
                step(
                    .raisePH,
                    "Ask your extension officer whether this low pH needs any change for flooded rice.",
                    "This pH was measured on drained soil, and flooding often moves pH toward neutral, so it is worth checking first.",
                    "Before next planting", .soil),
                step(
                    .checkNutrientBalance,
                    "Ask your extension officer to check the balance of nitrogen, phosphorus and potassium before adding more.",
                    "Nitrogen, phosphorus and potassium need to be in balance, and these readings are not.",
                    "Before next application", .soil),
                step(
                    .boostPotassium,
                    "Leave crop straw on the field after harvest to return potassium to the soil.",
                    "Potassium is low, and plants use it for strong stems.", "After harvest", .soil),
                step(
                    .keepStrawOnTop,
                    "Leave fresh straw on the surface as mulch instead of digging it into wet soil.",
                    "Organic carbon is very high, so fresh straw is better left on the surface.",
                    "After harvest", .soil),
                step(
                    .unlockPhosphorus,
                    "Add well-rotted compost so the phosphorus already in the soil can be used by plants.",
                    "Phosphorus is low, and roots need it to grow strong.", "Before planting", .soil),
            ]
            let organisms: [Organism] = [
                Organism(
                    name: "Ciliates", count: 28, perFrame: 2.33,
                    about: "Graze on bacteria and release nutrients plants can use."),
                Organism(
                    name: "Rotifers", count: 11, perFrame: 0.92,
                    about: "Feed on bacteria and organic particles in water films."),
                Organism(
                    name: "Nematodes", count: 4, perFrame: 0.33,
                    about: "Many feeding roles, some helpful and some harmful."),
            ]
            let single = HistoryPoint(
                date: now, perFrame: 3.58, moisture: "Flooded", isThisSample: true,
                byGroup: ["Ciliates": 2.33, "Rotifers": 0.92, "Nematodes": 0.33])
            return AdviceReport(
                farmName: "Subak Jatiluwih", farmerName: "Pak Wayan", areaText: "1.29 ha · 12,900 m²",
                plotName: "North", sampledAt: now, generatedAt: now, moisture: "Flooded",
                cropStage: "Tillering", recentActions: ["Fertilized"], framesKept: 12, totalCount: 43,
                organisms: organisms,
                moreKinds: 0, levelTitle: "Some soil life", confidence: "Low",
                reasons: ["43 organisms were counted across 12 frames."],
                followUp: "Test the same plot again in 2 to 4 weeks.",
                education: AdviceEducation(soil), soilUpdatedAt: now,
                history: history.isEmpty ? [single] : history,
                frameSources: [],
                recommendation: Recommendation(
                    summary: "Some soil life was seen, and the soil measurements point to a few changes too.",
                    noticed: [],
                    steps: Array(all.prefix(steps)),
                    source: .rules),
                basis:
                    "Based on 43 organisms (3 kinds) in 12 frames, flooded, and soil measurements (N, P, K, pH, organic carbon).",
                adviceNote: nil)
        }
    }

    #Preview("Report pages") {
        let pages = AdviceReportPages.pages(for: .sample())
        ScrollView {
            VStack(spacing: 16) {
                ForEach(pages.indices, id: \.self) { index in
                    pages[index]
                        .scaleEffect(0.62)
                        .frame(width: 595 * 0.62, height: 842 * 0.62)
                        .shadow(radius: 3)
                }
            }
            .padding()
        }
    }
#endif
