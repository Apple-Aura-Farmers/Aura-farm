//
//  FarmDetailView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// One farm, with everything known about it in one place: the plots on the map, what the
/// field helper has recorded about the soil, the tests the microscope operator has taken, and
/// what to do next.
struct FarmDetailView: View {
    /// Looked up in the store each time, so the page shows changes made by Edit straight away.
    let farmID: UUID

    @Environment(FarmStore.self) private var store
    /// The sheet showing over this page, if any. One at a time, so a single `sheet(item:)`.
    @State private var presented: Presentation?
    /// The tests taken on this farm, newest first. nil while they are being read from disk.
    @State private var tests: [FarmTest]?
    /// The plot waiting on a yes to being deleted.
    @State private var plotToDelete: Plot?

    private enum Presentation: String, Identifiable {
        case editFarm
        case soilMeasurements

        var id: String { rawValue }
    }

    private var farm: Farm? { store.farms.first { $0.id == farmID } }

    var body: some View {
        Group {
            if let farm {
                details(for: farm)
                    .navigationTitle(farm.name)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit") { presented = .editFarm }
                        }
                    }
                    .sheet(item: $presented) { presentation in
                        switch presentation {
                        case .editFarm:
                            FarmFormView(editing: farm)
                        case .soilMeasurements:
                            SoilMeasurementsForm(farm: farm)
                        }
                    }
                    .confirmationDialog(
                        "Delete this plot?",
                        isPresented: Binding(
                            get: { plotToDelete != nil },
                            set: { if !$0 { plotToDelete = nil } }),
                        presenting: plotToDelete
                    ) { plot in
                        Button("Delete plot \(farm.number(of: plot))", role: .destructive) {
                            Task { await remove(plot, from: farm) }
                        }
                    } message: { _ in
                        Text(
                            "The plot's outline will be removed from this phone and the "
                                + "records."
                        )
                    }
            } else {
                ContentUnavailableView("This farm is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(for farm: Farm) -> some View {
        List {
            if !farm.allCorners.isEmpty {
                Section {
                    LandMapView(outlines: farm.plots.map(\.corners), isInteractive: true)
                        .id(farm.allCorners)
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Farm") {
                LabeledContent("Farmer", value: farm.farmerName)
                if let area = farm.areaSquareMetres {
                    LabeledContent(
                        "Total area", value: LandGeometry.areaDescription(squareMetres: area))
                }
                LabeledContent("Added") {
                    Text(farm.createdAt, format: .dateTime.day().month().year())
                }
            }

            plots(of: farm)

            soilSection(for: farm)

            labResultsSection

            adviceSection(for: farm)
        }
        .task(id: farm.id) {
            let id = farm.id
            tests = await Task.detached(priority: .userInitiated) {
                FarmTests.load(for: id)
            }.value
        }
    }

    // MARK: Soil measurements

    /// What the field helper has recorded: only the values that are filled in.
    private func soilSection(for farm: Farm) -> some View {
        Section {
            if let soil = farm.soil, !soil.isEmpty {
                ForEach(soil.rows) { row in
                    SoilMeasurementRow(row: row)
                }
            } else {
                Text("Nothing recorded yet.")
                    .foregroundStyle(.secondary)
            }
            Button(
                farm.soil?.isEmpty == false ? "Edit measurements" : "Add measurements",
                systemImage: "square.and.pencil"
            ) {
                presented = .soilMeasurements
            }
        } header: {
            Text("Soil measurements")
        } footer: {
            if let soil = farm.soil, !soil.isEmpty {
                Text(
                    "Updated \(soil.updatedAt.formatted(date: .abbreviated, time: .omitted)). "
                        + "Tap a value for what it means. The standards and guidance are placeholders and have not been reviewed by an agronomist."
                )
            }

            Section {
                PublishButton(title: "Publish farm") {
                    guard let uploader = FarmUploader() else {
                        throw FarmUploader.Failure.notConfigured
                    }
                    try await uploader.upload(farm)
                }
            } footer: {
                Text(
                    "A sample can only be filed against land the records already know, so "
                        + "publish the farm before taking one from it."
                )
            }
        }
    }

    private func plots(of farm: Farm) -> some View {
        Section {
            ForEach(farm.plots) { plot in
                NavigationLink {
                    LandOutlineEditorView(
                        corners: plot.corners,
                        neighbours: store.farms.neighbours(excluding: plot.id)
                    ) { corners in
                        replace(plot, with: corners, in: farm)
                    }
                } label: {
                    row(for: plot, in: farm)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        plotToDelete = plot
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            NavigationLink {
                LandOutlineEditorView(
                    corners: [], neighbours: store.farms.neighbours()
                ) { corners in
                    add(corners, to: farm)
                }
            } label: {
                Label("Add a plot", systemImage: "plus")
            }
        } header: {
            Text("Plots")
        } footer: {
            if farm.plots.isEmpty {
                Text("Mark each piece of this farmer's land as its own plot.")
            }
        }
    }

    private func row(for plot: Plot, in farm: Farm) -> some View {
        HStack(spacing: 14) {
            FarmOutlineThumbnail(corners: plot.corners)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plot \(farm.number(of: plot))")
                    .font(.headline)
                if let area = plot.areaSquareMetres {
                    Text(LandGeometry.areaDescription(squareMetres: area))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Changing the plots

    private func add(_ corners: [GeoPoint], to farm: Farm) {
        var changed = farm
        changed.plots.append(Plot(corners: corners))
        store.update(changed)
    }

    private func replace(_ plot: Plot, with corners: [GeoPoint], in farm: Farm) {
        guard let index = farm.plots.firstIndex(where: { $0.id == plot.id }) else { return }
        var changed = farm
        changed.plots[index].corners = corners
        store.update(changed)
    }

    /// Takes the plot out of the records first, so one deleted here but left there does not
    /// come back with the next pull.
    private func remove(_ plot: Plot, from farm: Farm) async {
        if let uploader = FarmUploader() {
            do {
                try await uploader.delete(plot)
            } catch {
                store.report(error.localizedDescription)
                return
            }
        }
        var changed = farm
        changed.plots.removeAll { $0.id == plot.id }
        store.update(changed)
    }

    // MARK: Lab results

    private var labResultsSection: some View {
        Section {
            if let tests {
                if tests.isEmpty {
                    Text("No tests on this farm yet.")
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
            Text("Tests the microscope operator takes on this farm show here.")
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

    /// Advice for the farm's most recent counted test, written with the farm's soil measurements.
    @ViewBuilder
    private func adviceSection(for farm: Farm) -> some View {
        if let latest = tests?.first {
            FarmAdvice(test: latest, soil: farm.soil)
                // A new test, or different soil measurements, is new advice, so a fresh view model
                // for it. It then shows the saved advice if that still fits, and writes it again
                // if it doesn't.
                .id(AdviceKey(test: latest.id, soil: SoilInputs(farm.soil)))
        } else if tests?.isEmpty == true {
            Section {
                Text("Advice shows here once the microscope operator has tested this farm.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("What to do next")
            }
        }
    }
}

/// What the advice on a farm's page is for. When it changes, the advice is looked at afresh.
private struct AdviceKey: Hashable {
    let test: URL
    let soil: SoilInputs?
}

/// "What to do next" for one test. Owns the view model so it survives redraws.
private struct FarmAdvice: View {
    @State private var viewModel: SoilResultViewModel
    private let testedOn: Date
    private let usesSoil: Bool

    init(test: FarmTest, soil: SoilMeasurements?) {
        testedOn = test.result.recordedAt
        usesSoil = SoilInputs(soil) != nil
        var result = test.result
        result.soil = soil
        _viewModel = State(wrappedValue: SoilResultViewModel(result: result))
    }

    var body: some View {
        WhatToDoNextSection(
            viewModel: viewModel,
            footer: "From the microscope test on "
                + "\(testedOn.formatted(date: .abbreviated, time: .omitted))"
                + (usesSoil
                    ? ", with the soil measurements above. They don't change which steps are suggested yet."
                    : " only.")
        )
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
        FarmDetailView(farmID: farm.id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}
