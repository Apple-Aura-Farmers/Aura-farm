//
//  FarmDetailView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// One farm, with everything known about it in one place: the land on the map, what the field
/// helper has recorded about the soil, the tests the microscope operator has taken, and what to
/// do next.
struct FarmDetailView: View {
    /// Looked up in the store each time, so the page shows changes made by Edit straight away.
    let farmID: UUID

    @Environment(FarmStore.self) private var store
    /// The sheet showing over this page, if any. One at a time, so a single `sheet(item:)`.
    @State private var presented: Presentation?
    /// The tests taken on this farm, newest first. nil while they are being read from disk.
    @State private var tests: [FarmTest]?

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
                    .navigationTitle(farm.farmerName)
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
            } else {
                ContentUnavailableView("This farm is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(for farm: Farm) -> some View {
        List {
            Section {
                LandMapView(corners: farm.corners, isInteractive: true)
                    .id(farm.corners)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }

            Section("Land") {
                if let area = farm.areaSquareMetres {
                    LabeledContent(
                        "Area", value: LandGeometry.areaDescription(squareMetres: area))
                }
                LabeledContent("Corners", value: "\(farm.corners.count)")
                LabeledContent("Added") {
                    Text(farm.createdAt, format: .dateTime.day().month().year())
                }
            }

            soilSection(for: farm)

            labResultsSection

            adviceSection
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
                    LabeledContent(row.label, value: row.value)
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
                Text("Updated \(soil.updatedAt.formatted(date: .abbreviated, time: .omitted)).")
            }
        }
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

    /// Advice for the farm's most recent counted test.
    @ViewBuilder
    private var adviceSection: some View {
        if let latest = tests?.first {
            FarmAdvice(test: latest)
                // A new test is a new piece of advice, so a fresh view model for it.
                .id(latest.id)
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

/// "What to do next" for one test. Owns the view model so it survives redraws.
private struct FarmAdvice: View {
    @State private var viewModel: SoilResultViewModel
    private let testedOn: Date

    init(test: FarmTest) {
        testedOn = test.result.recordedAt
        _viewModel = State(wrappedValue: SoilResultViewModel(result: test.result))
    }

    var body: some View {
        WhatToDoNextSection(
            viewModel: viewModel,
            footer: "From the microscope test on "
                + "\(testedOn.formatted(date: .abbreviated, time: .omitted)) only. "
                + "The soil measurements above are not used in this advice yet."
        )
    }
}

#Preview {
    let farm = Farm(
        farmerName: "Pak Wayan",
        corners: [
            GeoPoint(latitude: -8.4095, longitude: 115.1889),
            GeoPoint(latitude: -8.4095, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1889),
        ])
    NavigationStack {
        FarmDetailView(farmID: farm.id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}
