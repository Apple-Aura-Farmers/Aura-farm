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
    /// The day a new measurement is for, when it is opened from a day that has none yet.
    var day: Date? = nil

    /// Where the Recommendation button scrolls to: the start of "What to do next".
    static let adviceID = "advice"

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = SoilMeasurements()
    /// Set once from the farm, so reopening does not wipe what is being typed.
    @State private var hasLoaded = false
    /// The tests taken on this plot, newest first. nil while they are read from disk.
    @State private var tests: [FarmTest]?
    @State private var isSaving = false
    /// Opening an existing reading shows it read-only until Edit is tapped; a new one has nothing to read yet.
    @State private var isEditing: Bool
    @State private var keyboardShown = false

    init(farmID: UUID, plotID: UUID, entryID: UUID? = nil, day: Date? = nil) {
        self.farmID = farmID
        self.plotID = plotID
        self.entryID = entryID
        self.day = day
        // A day opened from the list is read first, even when only a lab test was taken that day.
        _isEditing = State(initialValue: entryID == nil && day == nil)
    }

    /// A new measurement has no lab test yet, so none is shown (or used for advice) until it is saved.
    private var labTests: [FarmTest]? { entryID == nil && day == nil && isEditing ? [] : tests }

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
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancelEditing() }
                        .disabled(isSaving)
                }
            }
            ToolbarItem(placement: .principal) { title }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing { save() } else { isEditing = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEditing && (isSaving || !draft.problems.isEmpty))
            }
        }
        .task(id: plotID) {
            if !hasLoaded {
                if let entry = plot?.soilLog.first(where: { $0.id == entryID }) {
                    draft = entry
                } else if let day {
                    draft.measuredAt = day
                }
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
        ScrollViewReader { proxy in
            List {
                Group {
                    biodiversity(for: farm)
                    SoilMeasurementSections(draft: $draft, isEditable: isEditing)
                    if !isEditing { advice(for: farm) }
                    problems
                }
                .listRowBackground(Color.auraCard)
            }
            .listSectionSpacing(12)
            // The button rides above the keyboard and covers the field being typed in.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
                _ in
                keyboardShown = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
                _ in
                keyboardShown = false
            }
            .safeAreaInset(edge: .bottom) {
                if !isEditing, !keyboardShown, labTests?.isEmpty == false || SoilInputs(draft) != nil {
                    Button {
                        withAnimation { proxy.scrollTo(Self.adviceID, anchor: .top) }
                    } label: {
                        Label("Recommendation", systemImage: "sparkle")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [.indigo, .purple, .pink, .orange],
                                    startPoint: .leading, endPoint: .trailing),
                                in: .capsule)
                    }
                    .shadow(color: .purple.opacity(0.5), radius: 12)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: Biodiversity

    @ViewBuilder
    private func biodiversity(for farm: Farm) -> some View {
        Section("Biodiversity") {
            if let latest = labTests?.first {
                NavigationLink {
                    SoilResultScreen(sweep: latest.sweep)
                } label: {
                    BiodiversityRow(test: latest, others: (labTests?.count ?? 1) - 1)
                }
                .auraCardRow()
            } else if labTests == nil {
                ProgressView()
            } else {
                waitingCard(for: farm)
            }
        }
    }

    /// The two states before a result: nobody asked yet, and asked and waiting.
    private func waitingCard(for farm: Farm) -> some View {
        VStack(spacing: 14) {
            // An alert is answered once a test newer than it exists, so a later visit asks afresh.
            if let asked = plot?.scientistAlertedAt, asked > (tests?.first?.sweep.recordedAt ?? .distantPast)
            {
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
        if let plot, let tests = labTests {
            // The newest measurement, which may be this one or a later one already kept.
            let soil = SoilMeasurements.latest(in: plot.soilLog.filter { $0.id != draft.id } + [draft])
            // Without a test the advice comes from the measurements alone, once there are some.
            if tests.first != nil || SoilInputs(soil) != nil {
                FarmAdvice(farm: farm, plot: plot, test: tests.first, soil: soil, history: tests)
                    // A different test, or different numbers, is advice to look at afresh.
                    .id(AdviceKey(test: tests.first?.id, soil: SoilInputs(soil)))
            }
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

    /// Drops the changes and shows the kept reading again; a new reading has none, so it closes.
    private func cancelEditing() {
        guard let entry = plot?.soilLog.first(where: { $0.id == draft.id }) else {
            guard day != nil else { return dismiss() }
            // A day with only a lab test has no reading to go back to: it goes back to the test.
            draft = SoilMeasurements(measuredAt: day)
            isEditing = false
            return
        }
        draft = entry
        isEditing = false
    }

    private func save() {
        guard let farm, let plot, draft.problems.isEmpty else { return }
        var saved = draft
        saved.updatedAt = Date()
        draft = saved
        isSaving = true
        Task {
            await store.saveSoil(saved, for: plot, in: farm)
            isSaving = false
            isEditing = false
        }
    }
}

/// What the advice on this screen is for. When it changes, the advice is written again.
private struct AdviceKey: Hashable {
    let test: URL?
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(test.estimate.level.tint)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(test.estimate.level.tint)
            .scaleEffect(0.85)
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(test.estimate.level.title)
                    .font(.body)
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
        .padding(.vertical, 12)
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

#Preview {
    let farm = Farm(name: "Subak Jatiluwih", farmerName: "Pak Wayan", plots: [Plot(corners: [])])
    NavigationStack {
        SoilMeasurementsView(farmID: farm.id, plotID: farm.plots[0].id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}
