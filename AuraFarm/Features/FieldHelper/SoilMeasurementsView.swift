import SwiftUI

/// One plot's soil, as the helper meets it on the day: what the microscope found, what they
/// measured themselves, and what to do about it.
///
/// Biodiversity comes first because it is the thing the helper cannot read off a probe. Until
/// a scientist has looked at a sample there is nothing to show, so that card is the way to ask
/// for one; after that it is the waiting; after that it is the result, which opens in full.
/// The measurements below it are the helper's own: one visit's readings, new or an earlier one
/// being corrected, kept when Save is tapped, both on the phone and in the records.
struct SoilMeasurementsView: View {
    /// Looked up each time, so the screen follows changes made anywhere else.
    let farmID: UUID
    let plotID: UUID
    /// The measurement being edited, or nil to add a new one.
    var entryID: UUID? = nil

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = SoilMeasurements()
    /// Set once from the farm, so reopening does not wipe what is being typed.
    @State private var hasLoaded = false
    /// The tests taken on this plot, newest first. nil while they are read from disk.
    @State private var tests: [FarmTest]?
    @State private var isSaving = false

    private var farm: Farm? { store.farms.first { $0.id == farmID } }
    private var plot: Plot? { farm?.plots.first { $0.id == plotID } }

    var body: some View {
        Group {
            if let farm, plot != nil {
                form(for: farm)
                    .auraBackground()
            } else {
                ContentUnavailableView("This plot is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { title }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !draft.problems.isEmpty)
            }
        }
        .task(id: plotID) {
            if !hasLoaded, let entry = plot?.soilLog.first(where: { $0.id == entryID }) {
                draft = entry
            }
            hasLoaded = true
            guard let farm, let plot else { return }
            tests = await Task.detached(priority: .userInitiated) {
                FarmTests.load(for: plot, in: farm)
            }.value
        }
    }

    /// The day this is a reading of, which is what the helper calls it between visits.
    private var title: some View {
        VStack(spacing: 0) {
            Text(
                Calendar.current.isDateInToday(draft.measuredAt)
                    ? "Today" : draft.measuredAt.formatted(.dateTime.weekday(.wide))
            )
            .font(.headline)
            Text(draft.measuredAt, format: .dateTime.day().month(.abbreviated).year())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func form(for farm: Farm) -> some View {
        List {
            Group {
                biodiversity(for: farm)
                SoilMeasurementSections(draft: $draft, isEditable: true)
                advice(for: farm)
                problems
            }
            .listRowBackground(Color.auraRow)
        }
    }

    // MARK: Biodiversity

    @ViewBuilder
    private func biodiversity(for farm: Farm) -> some View {
        Section("Biodiversity") {
            if let latest = tests?.first {
                NavigationLink {
                    SoilResultScreen(sweep: latest.sweep)
                } label: {
                    BiodiversityRow(test: latest, others: (tests?.count ?? 1) - 1)
                }
            } else if tests == nil {
                ProgressView()
            } else {
                waitingCard(for: farm)
            }
        }
    }

    /// The two states before a result: nobody asked yet, and asked and waiting.
    private func waitingCard(for farm: Farm) -> some View {
        VStack(spacing: 14) {
            if let asked = plot?.scientistAlertedAt {
                Text("Wait for the scientist to send you the result.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Alerted") {}
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(true)
                Text("Asked \(asked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("You haven't assigned the scientist yet")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Send alert") {
                    guard let plot else { return }
                    Task { await store.alertScientist(for: plot, in: farm) }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: The helper's own measurements

    /// The advice for the newest test, written on the phone from these measurements.
    @ViewBuilder
    private func advice(for farm: Farm) -> some View {
        if let latest = tests?.first {
            // The newest measurement, which may be this one or a later one already kept.
            let soil = SoilMeasurements.latest(
                in: (plot?.soilLog ?? []).filter { $0.id != draft.id } + [draft])
            SoilAdviceSection(test: latest, soil: soil)
                // A different test, or different numbers, is advice to look at afresh.
                .id(AdviceKey(test: latest.id, soil: SoilInputs(soil)))
        }
    }

    @ViewBuilder
    private var problems: some View {
        if !draft.problems.isEmpty {
            Section {
                ForEach(draft.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func save(closing: Bool = true) {
        guard let farm, let plot, draft.problems.isEmpty else { return }
        var saved = draft
        saved.updatedAt = Date()
        draft = saved
        isSaving = true
        Task {
            await store.saveSoil(saved, for: plot, in: farm)
            isSaving = false
            if closing { dismiss() }
        }
    }
}

/// What the advice on this screen is for. When it changes, the advice is written again.
private struct AdviceKey: Hashable {
    let test: URL
    let soil: SoilInputs?
}

/// The result card: how much life the microscope found, how sure that is, and how many other
/// tests this farm has waiting behind it.
struct BiodiversityRow: View {
    let test: FarmTest
    var others = 0

    var body: some View {
        HStack(spacing: 14) {
            Gauge(value: Double(test.result.totalCount ?? 0), in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text(test.result.totalCount ?? 0, format: .number)
                    .font(.footnote)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(test.estimate.level.tint)
            .scaleEffect(0.85)
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(test.estimate.level.title)
                    .font(.headline)
                Text("Confidence: \(test.estimate.confidence.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if others > 0 {
                Text(others, format: .number)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.red, in: Circle())
                    .accessibilityLabel("\(others) more tests")
            }
        }
        .padding(.vertical, 6)
    }
}

/// Where the three nutrients sit together, from needing work to where they should be.
struct NutrientBar: View {
    let health: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 12)
                    .overlay(alignment: .leading) {
                        if let health {
                            Circle()
                                .fill(.white)
                                .frame(width: 18, height: 18)
                                .shadow(radius: 2)
                                .offset(x: (proxy.size.width - 18) * health)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 22)

            if health == nil {
                Text("Fill in a nutrient to see where this soil sits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: health)
    }
}

/// "What to do next" for one test, with these measurements. Owns the view model so it lives
/// across redraws of the screen around it.
private struct SoilAdviceSection: View {
    @State private var viewModel: SoilResultViewModel
    private let testedOn: Date

    init(test: FarmTest, soil: SoilMeasurements?) {
        testedOn = test.result.recordedAt
        var result = test.result
        result.soil = soil
        _viewModel = State(wrappedValue: SoilResultViewModel(result: result))
    }

    var body: some View {
        WhatToDoNextSection(
            viewModel: viewModel,
            footer: "From the microscope test on "
                + "\(testedOn.formatted(date: .abbreviated, time: .omitted)), with the "
                + "measurements above.")
    }
}

#Preview {
    let farm = Farm(name: "Subak Jatiluwih", farmerName: "Pak Wayan", plots: [Plot(corners: [])])
    NavigationStack {
        SoilMeasurementsView(farmID: farm.id, plotID: farm.plots[0].id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}
