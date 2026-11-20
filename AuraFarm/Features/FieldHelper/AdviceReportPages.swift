import Charts
import SwiftUI

/// The pages of the field report PDF, as SwiftUI views the size of an A4 sheet.
///
/// Three dense pages, laid out like a field sheet rather than a dashboard: a summary of the
/// sample, the soil measurements, and what to do next. A fourth page, "Trends and notes", only
/// appears when the steps are too many for the third. Each page has a fixed size and does not
/// scroll, and no text goes below 7.5 points.
///
/// Every word of advice comes from the report value, which carries the recommendation shown in
/// the app, steps and groups included. Nothing here writes or changes advice.
enum AdviceReportPages {
    /// Roughly how much of page 3 the steps and the extras may take before the extras move to a
    /// fourth page, in points.
    static let pageThreeBudget: CGFloat = 690

    /// How the third page's extras are shared out: all on page 3, or "About your soil
    /// measurements" on page 3 and the trend and notes on a fourth.
    enum Layout { case compact, split }

    static func titles(for report: AdviceReport) -> [String] {
        // Without a microscope test the summary has nothing to say, so the report starts with the soil.
        var titles = report.hasTest ? ["Field summary"] : []
        if report.education != nil { titles.append("Your soil measurements") }
        titles.append("What to do next")
        if report.hasTest, layout(for: report) == .split { titles.append("Trends and notes") }
        return titles
    }

    /// With no soil measurements and no fertilizer recorded there is nothing for a page of cards to
    /// show, so the report goes from the summary straight to what to do next.
    static func pages(for report: AdviceReport) -> [AnyView] {
        let layout = layout(for: report)
        let names = titles(for: report)
        let total = names.count
        var pages: [AnyView] = []
        for (index, name) in names.enumerated() {
            let number = index + 1
            switch name {
            case "Field summary":
                pages.append(
                    AnyView(
                        ReportPage(report: report, section: name, number: number, total: total) {
                            SummaryPage(report: report)
                        }))
            case "Your soil measurements":
                pages.append(
                    AnyView(
                        ReportPage(report: report, section: name, number: number, total: total) {
                            MeasurementsPage(report: report)
                        }))
            case "What to do next":
                pages.append(
                    AnyView(
                        ReportPage(report: report, section: name, number: number, total: total) {
                            NextStepsPage(report: report, layout: layout)
                        }))
            default:
                pages.append(
                    AnyView(
                        ReportPage(report: report, section: name, number: number, total: total) {
                            VStack(alignment: .leading, spacing: 14) {
                                TrendBlock(report: report, chartHeight: 340)
                                NotesBlock(report: report)
                            }
                        }))
            }
        }
        return pages
    }

    /// A rough measure, in points, of the steps table and the extras, to decide if they fit on one
    /// page. Worked out from rendered pages; the page has about 718 points.
    static func layout(for report: AdviceReport) -> Layout {
        if report.hasTest, report.hasTrend { return .split }
        let steps = CGFloat(report.recommendation.steps.count)
        let items = (report.education?.items.count ?? 0)
        let fertilizer: CGFloat = report.education?.fertilizer == nil ? 0 : 36
        let table: CGFloat = 150 + steps * 42
        let about: CGFloat = report.education == nil ? 0 : 14 + CGFloat(items) * 14 + fertilizer
        let extras: CGFloat = 30 + about + 160 + 24
        return table + extras > pageBudget ? .split : .compact
    }

    static let pageBudget: CGFloat = 718
}

// MARK: - Look

private enum Style {
    // Cool print palette: white stock, blue-black ink, one ink-blue accent. The status colours are
    // muted so they read like a second ink, not like interface colours.
    static let paper = Color(red: 0.992, green: 0.992, blue: 0.988)
    static let ink = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let muted = Color(red: 0.38, green: 0.41, blue: 0.46)
    static let accent = Color(red: 0.10, green: 0.25, blue: 0.43)
    static let good = Color(red: 0.14, green: 0.38, blue: 0.31)
    static let amber = Color(red: 0.62, green: 0.43, blue: 0.06)
    static let rust = Color(red: 0.55, green: 0.15, blue: 0.18)
    static let line = Color(red: 0.76, green: 0.78, blue: 0.82)
    static let panel = Color(red: 0.950, green: 0.955, blue: 0.965)
    static let slate = Color(red: 0.30, green: 0.42, blue: 0.48)

    /// One colour for each organism group, in a fixed order.
    static let groups: [Color] = [accent, amber, rust, slate, muted]

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
    date.formatted(date: .abbreviated, time: .omitted)
}

private func perFrame(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
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

    private var place: String {
        report.plotName.map { String(localized: "Plot \($0)") } ?? report.farmName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Aura Farm").font(Style.body(10, weight: .bold))
                    + Text(verbatim: "   \(section.translated)").font(Style.body(10)).foregroundColor(
                        Style.muted))
                Spacer()
                Text("\(place) · \(day(report.sampledAt)) · \(number)/\(total)")
                    .font(Style.mono(8, weight: .regular))
                    .foregroundStyle(Style.muted)
            }
            Rectangle().fill(Style.ink).frame(height: 1).padding(.top, 5)

            content
                .padding(.top, 12)

            Spacer(minLength: 6)

            Rectangle().fill(Style.line).frame(height: 0.5)
            Text(
                "For monitoring and learning, not a diagnosis. Standards are provisional and not yet reviewed by an agronomist. Ask an extension officer before making a major change."
            )
            .font(Style.body(7.5))
            .foregroundStyle(Style.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
        .padding(.horizontal, 44)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Style.paper)
        .foregroundStyle(Style.ink)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Small parts

private func smallCaps(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(Style.body(9.5, weight: .bold))
        .foregroundStyle(Style.accent)
}

private func labelled(_ label: LocalizedStringKey, _ text: String, size: CGFloat = 8.5) -> some View {
    (Text(label).font(Style.body(size, weight: .semibold)).foregroundColor(Style.muted)
        + Text(verbatim: "  ").font(Style.body(size, weight: .semibold))
        + Text(text).font(Style.body(size)))
        .fixedSize(horizontal: false, vertical: true)
}

private func bullet(_ text: String, size: CGFloat = 9) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text("•")
        Text(text).fixedSize(horizontal: false, vertical: true)
    }
    .font(Style.body(size))
}

private func chip(_ text: String, color: Color) -> some View {
    Text(text)
        .font(Style.body(8, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(Rectangle().stroke(color, lineWidth: 0.8))
}

private struct Card<Content: View>: View {
    var fill: Color = .clear
    var stroke: Color = Style.line
    let content: Content

    init(fill: Color = .clear, stroke: Color = Style.line, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.stroke = stroke
        self.content = content()
    }

    var body: some View {
        content
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill)
            .overlay(Rectangle().stroke(stroke, lineWidth: 0.6))
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

    private var place: String {
        report.plotName.map { String(localized: "Plot \($0)") } ?? report.farmName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.levelTitle) in \(place)")
                    .font(Style.title(24))
                Text(subtitle)
                    .font(Style.body(9.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.recommendation.summary.translated)
                    .font(Style.body(11))
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            meetYourSoil
            HStack(alignment: .top, spacing: 10) {
                estimate.frame(width: 200)
                whatChanged
            }
            .fixedSize(horizontal: false, vertical: true)
            if report.history.count >= 2 { perFrameBars }
            if let frame = report.frames.first {
                FrameImage(frame: frame, height: 120)
            }
            startWith
            if report.education == nil {
                Text(
                    "No soil measurements or fertilizer information have been recorded for this farm. Adding nitrogen, phosphorus, potassium, pH, organic carbon and the fertilizer type on the farm's page shows where each sits against its standard, and adds soil steps to the advice."
                )
                .font(Style.body(9))
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
                CanCannotBox()
            }
        }
    }

    private var subtitle: String {
        var parts = [String(localized: "Farmer \(report.farmerName)")]
        if let area = report.areaText { parts.append(area) }
        let sampled = day(report.sampledAt)
        parts.append(String(localized: "Sampled \(sampled)"))
        parts.append(report.moisture)
        if let stage = report.cropStage { parts.append(stage) }
        if !report.recentActions.isEmpty {
            let done = report.recentActions.joined(separator: ", ").lowercased()
            parts.append(String(localized: "Done recently: \(done)"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Organisms

    private var meetYourSoil: some View {
        VStack(alignment: .leading, spacing: 6) {
            smallCaps("Meet your soil")
            if report.organisms.isEmpty {
                Text("Nothing was counted in this sample.")
                    .font(Style.body(10))
                    .foregroundStyle(Style.muted)
            } else {
                let shown = Array(report.organisms.prefix(6))
                let rows = stride(from: 0, to: shown.count, by: 3).map {
                    Array(shown[$0..<min($0 + 3, shown.count)])
                }
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(0..<3, id: \.self) { column in
                            if column < rows[row].count {
                                organismCard(rows[row][column])
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if report.organisms.count > 6 || report.moreKinds > 0 {
                    let extra = report.organisms.dropFirst(6).map(\.name)
                    let names =
                        extra.isEmpty
                        ? String(localized: "\(report.moreKinds) more kinds") : extra.joined(separator: ", ")
                    Text("Also counted: \(names).")
                        .font(Style.body(8.5))
                        .foregroundStyle(Style.muted)
                }
                Text("\(countLine) Icons show the kind of organism, not an image from this sample.")
                    .font(Style.body(7.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var countLine: String {
        guard let total = report.totalCount else { return "" }
        return total == 1
            ? String(localized: "1 organism counted across \(report.framesKept) frames.")
            : String(localized: "\(total) organisms counted across \(report.framesKept) frames.")
    }

    private func organismCard(_ organism: AdviceReport.Organism) -> some View {
        Card(fill: .white) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "microbe")
                        .font(.system(size: 16))
                        .foregroundStyle(Style.accent)
                        .frame(width: 28, height: 28)
                        .background(Style.panel)
                    Text(organism.name)
                        .font(Style.body(11, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(organism.count) found · \(perFrame(organism.perFrame)) per frame")
                    .font(Style.mono(8, weight: .regular))
                    .foregroundStyle(Style.accent)
                if let about = organism.about {
                    Text(about)
                        .font(Style.body(8.5))
                        .foregroundStyle(Style.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Estimate and change

    private var estimate: some View {
        Card(fill: Style.panel, stroke: .clear) {
            VStack(alignment: .leading, spacing: 5) {
                smallCaps("Soil life estimate")
                Text(report.levelTitle).font(Style.title(15))
                Text("\(report.confidence) confidence")
                    .font(Style.body(9, weight: .medium))
                    .foregroundStyle(Style.amber)
                ForEach(report.reasons, id: \.self) { bullet($0, size: 8.5) }
                Text(report.followUp)
                    .font(Style.body(8.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var whatChanged: some View {
        VStack(alignment: .leading, spacing: 6) {
            smallCaps("What changed since the last sample")
            if let current = report.history.last(where: \.isThisSample),
                let previous = report.previousComparable
            {
                let names = Array(current.byGroup.sorted { $0.value > $1.value }.prefix(3).map(\.key))
                HStack(alignment: .top, spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        changeCard(name, now: current.byGroup[name] ?? 0, before: previous.byGroup[name] ?? 0)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Compared with the sample of \(day(previous.date)), taken in the same water state. Small changes between samples are normal."
                )
                .font(Style.body(7.5))
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    "This is the first comparable sample for this farm. The next one, taken in the same water state, will show what changed."
                )
                .font(Style.body(9.5))
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func changeCard(_ name: String, now: Double, before: Double) -> some View {
        let change = now - before
        let word =
            abs(change) <= max(before * 0.1, 0.1)
            ? String(localized: "Steady") : (change > 0 ? String(localized: "Up") : String(localized: "Down"))
        return Card(fill: .white) {
            VStack(alignment: .leading, spacing: 2) {
                Text(word)
                    .font(Style.body(8, weight: .bold))
                    .foregroundStyle(Style.accent)
                Text(name).font(Style.body(9.5, weight: .semibold))
                Text("\(perFrame(now)) per frame")
                    .font(Style.body(8.5))
                Text("was \(perFrame(before))")
                    .font(Style.body(8))
                    .foregroundStyle(Style.muted)
            }
        }
    }

    // MARK: Bars

    private var perFrameBars: some View {
        let points = Array(report.history.suffix(4))
        let names = orderedGroups(points)
        let top = max(points.map(\.perFrame).max() ?? 1, 0.1)
        return VStack(alignment: .leading, spacing: 5) {
            smallCaps("Soil life per frame, by test")
            ForEach(points.indices, id: \.self) { index in
                let point = points[index]
                HStack(spacing: 8) {
                    Text("\(day(point.date)) · \(point.moisture.lowercased())")
                        .font(Style.body(8.5, weight: point.isThisSample ? .semibold : .regular))
                        .frame(width: 118, alignment: .leading)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(names.indices, id: \.self) { column in
                                let value = point.byGroup[names[column]] ?? 0
                                Rectangle()
                                    .fill(Style.groups[column % Style.groups.count])
                                    .frame(width: proxy.size.width * value / top)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 10)
                    Text(perFrame(point.perFrame))
                        .font(Style.body(8.5, weight: .medium))
                        .frame(width: 34, alignment: .trailing)
                }
            }
            HStack(spacing: 10) {
                ForEach(names.indices, id: \.self) { column in
                    HStack(spacing: 3) {
                        Rectangle().fill(Style.groups[column % Style.groups.count]).frame(width: 6, height: 6)
                        Text(names[column]).font(Style.body(7.5))
                    }
                }
            }
            Text(
                "Organisms counted per microscope frame. Counts from flooded and drained fields are not directly comparable."
            )
            .font(Style.body(7.5))
            .foregroundStyle(Style.muted)
        }
    }

    /// The groups across the tests, most counted first, at most five.
    private func orderedGroups(_ points: [AdviceReport.HistoryPoint]) -> [String] {
        var totals: [String: Double] = [:]
        for point in points {
            for (name, value) in point.byGroup { totals[name, default: 0] += value }
        }
        return totals.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    // MARK: Start with

    @ViewBuilder
    private var startWith: some View {
        if let first = report.recommendation.steps.first {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start with")
                    .font(Style.body(8.5, weight: .bold))
                    .foregroundStyle(Style.accent)
                Text(first.text.translated)
                    .font(Style.body(11, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let why = first.why {
                    Text(why.translated).font(Style.body(9)).fixedSize(horizontal: false, vertical: true)
                }
                Text("All \(report.recommendation.steps.count) steps are on page 3.")
                    .font(Style.body(8))
                    .foregroundStyle(Style.muted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Style.panel)
            .overlay(alignment: .leading) { Rectangle().fill(Style.accent).frame(width: 3) }
        }
    }
}

// MARK: - Page 2: soil measurements

private struct MeasurementsPage: View {
    let report: AdviceReport

    private let slots = ["Nitrogen", "Phosphorus", "Potassium", "pH", "Organic carbon"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your soil measurements").font(Style.title(22))
                Text(intro)
                    .font(Style.body(9.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let cells = cardViews()
            ForEach(0..<3, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    cells[row * 2]
                    cells[row * 2 + 1]
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            CanCannotBox()
        }
    }

    private func cardViews() -> [AnyView] {
        var views: [AnyView] = []
        for name in slots {
            if let item = report.education?.items.first(where: { $0.name == name }) {
                views.append(AnyView(measurementCard(item)))
            } else {
                views.append(AnyView(missingCard(name)))
            }
        }
        views.append(AnyView(fertilizerCard))
        return views
    }

    private var intro: String {
        var text = String(
            localized:
                "Recorded by the field helper, separately from the microscope. Each reading is placed against provisional standards for flooded rice, not graded."
        )
        if let updated = report.soilUpdatedAt {
            let measured = day(updated)
            text += " " + String(localized: "Measured \(measured).")
        }
        return text
    }

    private func measurementCard(_ item: AdviceEducation.Item) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name.translated).font(Style.body(10.5, weight: .semibold))
                    Spacer()
                    chip(item.band.translated, color: Style.color(for: item.tone))
                }
                Text(item.value).font(Style.mono(16))
                RangeBar(standard: item.standard, value: item.number)
                if let context = item.context {
                    Text(context).font(Style.body(8)).foregroundStyle(Style.muted)
                }
                labelled("What it does", item.whatItDoes.translated)
                labelled("This reading", item.meaning.translated)
                labelled("What to do", (item.action ?? SoilEducation.noChange).translated)
            }
        }
    }

    private func missingCard(_ name: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(name.translated).font(Style.body(10.5, weight: .semibold)).foregroundStyle(Style.muted)
                Text("Not recorded").font(Style.title(14)).foregroundStyle(Style.muted)
                Text("No reading was entered for this farm, so nothing is shown or assumed.")
                    .font(Style.body(8.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fertilizerCard: some View {
        Card(fill: Style.panel, stroke: .clear) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Fertilizer").font(Style.body(10.5, weight: .semibold))
                if let fertilizer = report.education?.fertilizer {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(fertilizer.label.translated).font(Style.title(14))
                        Spacer()
                        if let verdict = fertilizer.verdict {
                            chip(verdict.translated, color: Style.color(for: fertilizer.tone))
                        }
                    }
                    if let details = fertilizer.details {
                        labelled("Recorded", details)
                    }
                    Text(fertilizer.definition.translated)
                        .font(Style.body(8.5))
                        .fixedSize(horizontal: false, vertical: true)
                    if let effect = fertilizer.effect {
                        labelled("On paddy soil", effect.translated)
                    }
                } else {
                    Text("Not recorded").font(Style.title(14)).foregroundStyle(Style.muted)
                    Text("No fertilizer type was chosen. Nothing is assumed about what was used.")
                        .font(Style.body(8.5))
                        .foregroundStyle(Style.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CanCannotBox: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("What the microscope can show")
                    .font(Style.body(9.5, weight: .semibold))
                    .foregroundStyle(Style.accent)
                Text(
                    "How many small organisms of each group live in a drop of soil water, counted per frame, and whether that changes between samples taken in the same water state."
                )
                .font(Style.body(8.5))
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
                .font(Style.body(8.5))
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Style.panel)
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

// MARK: - Page 3: what to do next

private struct NextStepsPage: View {
    let report: AdviceReport
    let layout: AdviceReportPages.Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What to do next").font(Style.title(22))
                Text(report.recommendation.summary.translated)
                    .font(Style.body(11))
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceLine)
                    .font(Style.body(8.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            stepsTable

            if let basis = report.basis {
                Text(basis)
                    .font(Style.body(8.5))
                    .foregroundStyle(Style.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if layout == .compact, report.hasTest {
                TrendBlock(report: report, chartHeight: 0)
            }
            if let education = report.education { AboutBlock(education: education) }
            if layout == .compact {
                NotesBlock(report: report)
            }
        }
    }

    private var sourceLine: String {
        var text = report.recommendation.source.label.translated + "."
        if let note = report.adviceNote { text += " " + note }
        return text
    }

    private enum Row {
        case header(String)
        case step(Int, Recommendation.Step)
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var last: Recommendation.Step.Group?
        var started = false
        for (index, step) in report.recommendation.steps.enumerated() {
            if !started || step.group != last {
                if let group = step.group {
                    let title =
                        group == .microscope
                        ? String(localized: "From the microscope test")
                        : String(localized: "From your soil measurements")
                    rows.append(.header(title))
                }
                last = step.group
                started = true
            }
            rows.append(.step(index + 1, step))
        }
        return rows
    }

    private var stepsTable: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("No.").frame(width: 18, alignment: .leading)
                Text("Step").frame(maxWidth: .infinity, alignment: .leading)
                Text("Why").frame(width: 175, alignment: .leading)
                Text("When").frame(width: 78, alignment: .leading)
            }
            .font(Style.body(8, weight: .bold))
            .foregroundStyle(Style.muted)
            .padding(.bottom, 4)

            ForEach(rows.indices, id: \.self) { index in
                Rectangle().fill(Style.line).frame(height: 0.5)
                switch rows[index] {
                case .header(let title):
                    Text(title)
                        .font(Style.body(8.5, weight: .bold))
                        .foregroundStyle(Style.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(Style.panel)
                case .step(let number, let step):
                    stepRow(step, number: number)
                }
            }
            Rectangle().fill(Style.line).frame(height: 0.5)
        }
    }

    private func stepRow(_ step: Recommendation.Step, number: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%02d", number))
                .font(Style.mono(9))
                .foregroundStyle(Style.accent)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.text.translated)
                    .font(Style.body(10, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if step.alsoFromSoil {
                    Text("Also supported by your soil measurements")
                        .font(Style.body(7.5, weight: .medium))
                        .foregroundStyle(Style.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(step.why?.translated ?? "")
                .font(Style.body(8.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 175, alignment: .leading)
            Text(step.timing?.translated ?? "")
                .font(Style.body(8.5, weight: .medium))
                .foregroundStyle(Style.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 78, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trend, education and notes

private struct TrendBlock: View {
    let report: AdviceReport
    /// 0 when there is only the message, which is all a page with no trend needs.
    let chartHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            smallCaps("Soil life over time")
            if report.hasTrend {
                TrendChart(report: report, height: max(chartHeight, 110))
                Text(
                    "Each point is one test. Counts from flooded and drained fields are not directly comparable, so the water state of each test is listed. A change over time is an association only: this chart does not show what caused it. Only the latest soil measurements are kept, so no soil trend can be shown."
                )
                .font(Style.body(8))
                .foregroundStyle(Style.muted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                (Text("More samples are needed before a trend can be shown.  ")
                    .font(Style.body(9, weight: .medium))
                    + Text("Only the latest soil measurements are kept, so no soil trend can be shown.")
                    .font(Style.body(8)).foregroundColor(Style.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AboutBlock: View {
    let education: AdviceEducation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            smallCaps("About your soil measurements")
            ForEach(education.items, id: \.name) { item in
                (Text(verbatim: "\(item.name.translated) · \(item.band.translated).  ")
                    .font(Style.body(8.5, weight: .semibold))
                    + Text(item.meaning.translated).font(Style.body(8.5)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let fertilizer = education.fertilizer {
                (Text("Fertilizer · \(fertilizer.label.translated).  ").font(
                    Style.body(8.5, weight: .semibold))
                    + Text(fertilizer.education ?? fertilizer.definition.translated).font(Style.body(8.5)))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NotesBlock: View {
    let report: AdviceReport

    private var phLine: String {
        guard let ph = report.education?.items.first(where: { $0.name == "pH" }) else {
            return String(localized: "No pH was recorded for this farm.")
        }
        if let context = ph.context { return String(localized: "This farm's pH reading: \(context).") }
        return String(
            localized: "How and when this farm's pH was measured was not recorded, so read it with care.")
    }

    private var madeLine: String {
        let shownOn = day(report.generatedAt)
        return [
            String(
                localized:
                    "The app's fixed rules chose every step from the microscope test and the soil measurements."
            ),
            report.recommendation.source == .foundationModel
                ? String(
                    localized:
                        "Apple Intelligence on the phone only wrote the wording, which was checked first.")
                : String(localized: "The wording is the app's standard advice."),
            String(localized: "This report shows the advice the app showed on \(shownOn)."),
        ].joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            smallCaps("Notes and limitations")
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    note(
                        "Standards",
                        String(
                            localized:
                                "A provisional first draft for flooded rice paddies. No agronomist has reviewed it yet."
                        )
                    )
                    note("pH in flooded rice", SoilEducation.phCaveat.translated + " " + phLine)
                    note(
                        "Using this report",
                        String(
                            localized:
                                "For monitoring and learning, not a diagnosis. Ask an extension officer before making a major change."
                        )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 5) {
                    note(
                        "Measurements",
                        String(
                            localized:
                                "Probe and laboratory readings can differ, and a reading depends on where, how deep and when the soil was sampled. Only the latest measurements are kept."
                        )
                    )
                    note(
                        "Fertilizer",
                        String(
                            localized:
                                "The type is what the field helper chose from a list. “No fertilizer recorded” does not mean none was used, and “Not sure” is never guessed at. No step gives a product, an amount or a rate."
                        )
                    )
                    note("How the advice was made", madeLine)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func note(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Style.body(8, weight: .semibold)).foregroundStyle(Style.accent)
            Text(text).font(Style.body(8)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrendChart: View {
    let report: AdviceReport
    let height: CGFloat

    private var names: [String] {
        var totals: [String: Double] = [:]
        for point in report.history {
            for (name, value) in point.byGroup { totals[name, default: 0] += value }
        }
        return totals.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    var body: some View {
        let shown = names
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(shown, id: \.self) { name in
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
                domain: shown, range: Array(Style.groups.prefix(max(shown.count, 1)))
            )
            .chartXScale(range: .plotDimension(padding: 22))
            .chartXAxisLabel("Sample date")
            .chartYAxisLabel("Organisms per frame")
            .chartXAxis {
                AxisMarks(values: report.history.map(\.date)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: height)

            Text(
                report.history.map { "\(day($0.date)): \($0.moisture.lowercased())" }
                    .joined(separator: " · ")
            )
            .font(Style.body(7.5))
            .foregroundStyle(Style.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
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
