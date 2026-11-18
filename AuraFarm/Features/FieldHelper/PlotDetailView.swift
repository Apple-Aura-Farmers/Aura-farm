//
//  PlotDetailView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 18/11/26.
//

import SwiftUI

/// One plot of a farm, with everything known about it in one place: where it is and how big,
/// what the field helper has recorded about its soil, the tests the microscope operator has
/// taken on it, and what to do next. Each plot has its own, so a test or a reading on one
/// plot never speaks for another.
struct PlotDetailView: View {
    /// Looked up in the store each time, so the page shows changes made anywhere else.
    let farmID: UUID
    let plotID: UUID

    @Environment(FarmStore.self) private var store
    /// The tests taken on this plot, newest first. nil while they are being read from disk.
    @State private var tests: [FarmTest]?

    private var farm: Farm? { store.farms.first { $0.id == farmID } }

    var body: some View {
        Group {
            if let farm, let plot = farm.plots.first(where: { $0.id == plotID }) {
                details(for: plot, in: farm)
                    .navigationTitle(farm.title(of: plot))
            } else {
                ContentUnavailableView("This plot is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .auraBackground()
    }

    private func details(for plot: Plot, in farm: Farm) -> some View {
        List {
            Group {
                if !plot.corners.isEmpty {
                    Section {
                        LandMapView(corners: plot.corners, isInteractive: true)
                            .id(plot.corners)
                            .frame(height: 260)
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section("Plot") {
                    LabeledContent("Farmer", value: farm.farmerName)
                    if !plot.name.isEmpty {
                        LabeledContent("Name", value: plot.name)
                    }
                    if let area = plot.areaSquareMetres {
                        LabeledContent(
                            "Total area", value: LandGeometry.areaDescription(squareMetres: area))
                    }
                    NavigationLink {
                        LandOutlineEditorView(
                            corners: plot.corners,
                            neighbours: store.farms.neighbours(excluding: plot.id),
                            confirmTitle: "Save"
                        ) { corners in
                            replace(plot, with: corners, in: farm)
                        }
                    } label: {
                        Label("Edit outline", systemImage: "square.dashed")
                    }
                }

                soilSection(for: plot)

                labResultsSection

                adviceSection(for: plot, in: farm)
            }
            .listRowBackground(Color.auraRow)
        }
        .task(id: plot.id) {
            tests = await Task.detached(priority: .userInitiated) {
                FarmTests.load(for: plot, in: farm)
            }.value
        }
    }

    private func replace(_ plot: Plot, with corners: [GeoPoint], in farm: Farm) {
        guard let index = farm.plots.firstIndex(where: { $0.id == plot.id }) else { return }
        var changed = farm
        changed.plots[index].corners = corners
        store.update(changed)
        store.publish(changed)
    }

    // MARK: Soil measurements

    /// The newest measurement, laid out as the editor is but read-only, then the log of every
    /// visit to open, change or delete. The advice is written from the newest.
    @ViewBuilder
    private func soilSection(for plot: Plot) -> some View {
        // Changing a measurement is done on its own page, not here.
        let today = plot.soilLog.filter { Calendar.current.isDateInToday($0.measuredAt) }
            .max { $0.updatedAt < $1.updatedAt }
        Section {
            NavigationLink {
                SoilMeasurementsView(farmID: farmID, plotID: plot.id, entryID: today?.id)
            } label: {
                Label(
                    today == nil ? "Add today's measurement" : "Edit today's measurement",
                    systemImage: "square.and.pencil")
            }
        }
        if let soil = plot.soil {
            // The same sections as the editor, which the helper opens from the log below.
            SoilMeasurementSections(
                draft: .constant(soil), isEditable: false,
                biodiversity: tests?.first {
                    Calendar.current.isDate($0.result.recordedAt, inSameDayAs: soil.measuredAt)
                })
        } else {
            Section("Soil measurements") {
                Text("Nothing recorded yet.")
                    .foregroundStyle(.secondary)
            }
        }
        let log = plot.soilLog.filter { !$0.isEmpty }.sorted { $0.measuredAt > $1.measuredAt }
        Section {
            ForEach(log) { entry in
                NavigationLink {
                    SoilMeasurementsView(farmID: farmID, plotID: plot.id, entryID: entry.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.measuredAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                        Text(entry.rows.map { "\($0.label) \($0.value)" }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                guard let farm else { return }
                let doomed = offsets.map { log[$0].id }
                Task { for id in doomed { await store.deleteSoil(id, for: plot, in: farm) } }
            }
        } header: {
            Text("Measurement log")
        } footer: {
            if !log.isEmpty { Text("Swipe left on a measurement to delete it.") }
        }
    }

    // MARK: Lab results

    private var labResultsSection: some View {
        Section {
            if let tests {
                if tests.isEmpty {
                    Text("No tests on this plot yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tests) { test in
                        NavigationLink {
                            SoilResultScreen(sweep: test.sweep)
                        } label: {
                            row(for: test)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Lab results")
        } footer: {
            Text("Tests the microscope operator takes on this plot show here.")
        }
    }

    /// One test: how much soil life it saw, when, and how sure that is. The band is never shown
    /// without its confidence; the reasons are one tap away on the full result.
    private func row(for test: FarmTest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: test.estimate.level.systemImage)
                .font(.title2)
                .foregroundStyle(test.estimate.level.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(test.estimate.level.title)
                    .font(.headline)
                Text(
                    test.result.recordedAt.formatted(date: .abbreviated, time: .shortened)
                        + " · \(test.result.moisture.label)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(detail(of: test))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(of test: FarmTest) -> String {
        var parts: [String] = []
        if let total = test.result.totalCount {
            parts.append(total == 1 ? "1 organism" : "\(total) organisms")
        }
        parts.append("\(test.estimate.confidence.label) confidence")
        return parts.joined(separator: " · ")
    }

    // MARK: What to do next

    /// Advice for the plot's most recent counted test, written with the plot's soil measurements.
    @ViewBuilder
    private func adviceSection(for plot: Plot, in farm: Farm) -> some View {
        if let latest = tests?.first {
            FarmAdvice(farm: farm, plot: plot, test: latest, history: tests ?? [])
                // A new test, or different soil measurements, is new advice, so a fresh view model
                // for it. It then shows the saved advice if that still fits, and writes it again
                // if it doesn't.
                .id(AdviceKey(test: latest.id, soil: SoilInputs(plot.soil)))
        } else if tests?.isEmpty == true {
            Section {
                Text("Advice shows here once the microscope operator has tested this plot.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("What to do next")
            }
        }
    }
}

/// What the advice on a plot's page is for. When it changes, the advice is looked at afresh.
private struct AdviceKey: Hashable {
    let test: URL
    let soil: SoilInputs?
}

/// "What to do next" for one test, and a way to export it. Owns the view model so it survives
/// redraws.
private struct FarmAdvice: View {
    @State private var viewModel: SoilResultViewModel
    private let farm: Farm
    private let plot: Plot
    private let test: FarmTest
    /// Every counted test of this farm, for the report's trend.
    private let history: [FarmTest]
    private let testedOn: Date
    private let usesSoil: Bool

    init(farm: Farm, plot: Plot, test: FarmTest, history: [FarmTest]) {
        self.farm = farm
        self.plot = plot
        self.test = test
        self.history = history
        testedOn = test.result.recordedAt
        usesSoil = SoilInputs(plot.soil) != nil
        var result = test.result
        result.soil = plot.soil
        _viewModel = State(wrappedValue: SoilResultViewModel(result: result))
    }

    var body: some View {
        Group {
            WhatToDoNextSection(
                viewModel: viewModel,
                footer: "From the microscope test on "
                    + "\(testedOn.formatted(date: .abbreviated, time: .omitted))"
                    + (usesSoil
                        ? ", with the soil measurements above."
                        : " only.")
            )
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
                    "A field report of this test, the soil measurements, the fertilizer and the advice above, to share or print."
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
