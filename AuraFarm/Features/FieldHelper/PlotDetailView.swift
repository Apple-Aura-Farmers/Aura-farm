//
//  PlotDetailView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 18/11/26.
//

import SwiftUI

/// One plot of a farm, as the tests taken on it: a row for each day with something recorded,
/// newest first, each saying what was measured that day. A day opens to its results and advice;
/// the plus button adds a measurement.
struct PlotDetailView: View {
    /// Looked up in the store each time, so the page shows changes made anywhere else.
    let farmID: UUID
    let plotID: UUID

    @Environment(FarmStore.self) private var store
    /// The tests taken on this plot, newest first. nil while they are being read from disk.
    @State private var tests: [FarmTest]?
    @State private var isEditingOutline = false

    private var farm: Farm? { store.farms.first { $0.id == farmID } }

    /// One day's worth of what was recorded on the plot.
    private struct Day: Identifiable {
        let date: Date
        let entries: [SoilMeasurements]
        let test: FarmTest?
        var id: Date { date }

        /// What was measured, as the chips under the date.
        var tags: [String] {
            let soil = entries.first
            var tags: [String] = []
            if soil?.npkHealth != nil { tags.append("NPK") }
            if test != nil { tags.append("Biodiversity") }
            if soil?.ph != nil { tags.append("pH") }
            if soil?.organicCarbonPercent != nil { tags.append("SOC") }
            if soil?.fertilizerSummary != nil { tags.append("Fertilizer") }
            return tags
        }
    }

    private func days(of plot: Plot) -> [Day] {
        let calendar = Calendar.current
        let log = plot.soilLog.filter { !$0.isEmpty }
        let dates = Set(log.map { calendar.startOfDay(for: $0.measuredAt) })
            .union((tests ?? []).map { calendar.startOfDay(for: $0.result.recordedAt) })
        return dates.sorted(by: >).map { date in
            Day(
                date: date,
                entries: log.filter { calendar.isDate($0.measuredAt, inSameDayAs: date) }
                    .sorted { $0.updatedAt > $1.updatedAt },
                test: tests?.first { calendar.isDate($0.result.recordedAt, inSameDayAs: date) })
        }
    }

    var body: some View {
        Group {
            if let farm, let plot = farm.plots.first(where: { $0.id == plotID }) {
                list(for: plot, in: farm)
                    .navigationTitle(farm.title(of: plot))
                    .navigationDestination(isPresented: $isEditingOutline) {
                        LandOutlineEditorView(
                            corners: plot.corners,
                            neighbours: store.farms.neighbours(excluding: plot.id),
                            confirmTitle: "Save"
                        ) { corners in
                            replace(plot, with: corners, in: farm)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                SoilMeasurementsView(farmID: farmID, plotID: plot.id)
                            } label: {
                                Label("Add measurement", systemImage: "plus")
                            }
                        }
                    }
            } else {
                ContentUnavailableView("This plot is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .auraBackground()
    }

    private func list(for plot: Plot, in farm: Farm) -> some View {
        let days = days(of: plot)
        return List {
            Group {
                if !plot.corners.isEmpty {
                    LandMapView(corners: plot.corners, isInteractive: true)
                        .id(plot.corners)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                isEditingOutline = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.headline)
                                    .padding(10)
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .accessibilityLabel("Edit plot outline")
                        }
                        .listRowInsets(EdgeInsets())
                }
                if tests != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tests")
                            .font(.title3.bold())
                        Text(days.count == 1 ? "1 test" : "\(days.count) tests")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 8, trailing: 4))
                }
                if tests == nil {
                    ProgressView()
                } else if days.isEmpty {
                    Text("Nothing measured yet. Tap + to add a measurement.")
                        .foregroundStyle(.secondary)
                }
                ForEach(days) { day in
                    NavigationLink {
                        SoilMeasurementsView(
                            farmID: farmID, plotID: plot.id, entryID: day.entries.first?.id,
                            day: day.date)
                    } label: {
                        row(for: day)
                    }
                    .swipeActions {
                        if !day.entries.isEmpty {
                            Button(role: .destructive) {
                                Task {
                                    for entry in day.entries {
                                        await store.deleteSoil(entry.id, for: plot, in: farm)
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16).fill(Color.auraRow))
            .listRowSeparator(.hidden)
        }
        .listRowSpacing(12)
        .task(id: plot.id) {
            tests = await Task.detached(priority: .userInitiated) {
                FarmTests.load(for: plot, in: farm)
            }.value
        }
    }

    private func row(for day: Day) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                Calendar.current.isDateInToday(day.date)
                    ? "Today" : day.date.formatted(date: .abbreviated, time: .omitted)
            )
            .font(.headline)
            ChipFlow(spacing: 6) {
                ForEach(day.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func replace(_ plot: Plot, with corners: [GeoPoint], in farm: Farm) {
        guard let index = farm.plots.firstIndex(where: { $0.id == plot.id }) else { return }
        var changed = farm
        changed.plots[index].corners = corners
        store.update(changed)
        store.publish(changed)
    }
}

/// What the advice on a plot's page is for. When it changes, the advice is looked at afresh.
private struct AdviceKey: Hashable {
    let test: URL
    let soil: SoilInputs?
}

/// "What to do next" for one test, and a way to export it. Owns the view model so it survives
/// redraws.
struct FarmAdvice: View {
    @State private var viewModel: SoilResultViewModel
    private let farm: Farm
    private let plot: Plot
    /// nil when no microscope test has been taken, and the advice is from the soil alone.
    private let test: FarmTest?
    /// Every counted test of this farm, for the report's trend.
    private let history: [FarmTest]
    private let testedOn: Date?
    private let usesSoil: Bool

    init(farm: Farm, plot: Plot, test: FarmTest?, soil: SoilMeasurements?, history: [FarmTest]) {
        self.farm = farm
        self.plot = plot
        self.test = test
        self.history = history
        testedOn = test?.result.recordedAt
        usesSoil = SoilInputs(soil) != nil
        var result =
            test?.result
            ?? SoilResult.soilOnly(
                soil ?? SoilMeasurements(), recordedAt: soil?.measuredAt ?? Date(),
                sampleID: farm.farmerName)
        result.soil = soil
        _viewModel = State(wrappedValue: SoilResultViewModel(result: result))
    }

    var body: some View {
        Group {
            WhatToDoNextSection(
                viewModel: viewModel,
                footer: testedOn.map {
                    "From the microscope test on "
                        + "\($0.formatted(date: .abbreviated, time: .omitted))"
                        + (usesSoil ? ", with the soil measurements above." : " only.")
                } ?? "From the soil measurements above only. A microscope test will add to it."
            )
            .id(SoilMeasurementsView.adviceID)
            exportSection
        }
    }

    /// Offered once the advice is written, so the PDF never shows an advice that is still loading.
    /// The PDF is written when a place to send it to is chosen, not before.
    @ViewBuilder
    private var exportSection: some View {
        if case .ready(let recommendation) = viewModel.recommendationState {
            Section {
                ShareLink(
                    // The report carries the advice exactly as it is on screen: the same
                    // recommendation, "Based on" line, step labels and note. It is rebuilt from the
                    // view model each time this redraws, so it never holds advice that was replaced.
                    item: ExportableAdvice(
                        report: AdviceReport.make(
                            farm: farm, plot: plot, test: test, recommendation: recommendation,
                            basis: viewModel.adviceBasis,
                            adviceNote: viewModel.modelUnavailableReason, history: history)),
                    preview: SharePreview("Field report for \(farm.name), \(farm.title(of: plot))")
                ) {
                    Label("Export field report as PDF", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text(
                    "A field report of the soil measurements, the microscope test if there is one, the fertilizer and the advice above, to share or print."
                )
            }
        }
    }
}

#Preview {
    let farm = Farm(
        name: "Subak Jatiluwih",
        farmerName: "Pak Wayan",
        plots: [
            Plot(corners: [
                GeoPoint(latitude: -8.4095, longitude: 115.1889),
                GeoPoint(latitude: -8.4095, longitude: 115.1900),
                GeoPoint(latitude: -8.4105, longitude: 115.1900),
                GeoPoint(latitude: -8.4105, longitude: 115.1889),
            ])
        ])
    NavigationStack {
        PlotDetailView(farmID: farm.id, plotID: farm.plots[0].id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}

/// Lays its children left to right and starts a new line when one no longer fits, so a chip
/// is moved down whole rather than broken across lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let placed = arrange(in: bounds.width, subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + rowHeight))
    }
}
