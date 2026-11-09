import AuraFarmKit
import Charts
import SwiftData
import SwiftUI

/// A field's growing seasons on its page: the current one with what has gone on against the
/// plan, earlier ones with their yield, and the yield over time.
struct SeasonsSection: View {
    let field: Field
    /// The field's plan, to measure what has gone on against. Empty without NPK results.
    let doses: [FertilizerDose]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.canEditRecords) private var canEdit
    @State private var isAddingSeason = false
    @State private var seasonToEdit: Season?
    @State private var seasonToDelete: Season?
    @State private var seasonForNewApplication: Season?
    @State private var applicationToEdit: FertilizerApplication?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seasons")
                    .font(.headline)
                Spacer()
                if canEdit {
                    Button("New Season") {
                        isAddingSeason = true
                    }
                }
            }

            if field.seasons.isEmpty {
                Text(
                    canEdit
                        ? "No seasons yet. Start one to record the variety, the transplanting date, the "
                            + "fertilizer put on and the harvest."
                        : "No seasons recorded yet."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(field.sortedSeasons) { season in
                    seasonCard(season, isCurrent: season.persistentModelID == currentSeasonID)
                }
                yieldChart
            }
        }
        .sheet(isPresented: $isAddingSeason) {
            SeasonEditorView(field: field, season: nil)
        }
        .sheet(item: $seasonToEdit) { season in
            SeasonEditorView(field: field, season: season)
        }
        .sheet(item: $seasonForNewApplication) { season in
            FertilizerApplicationEditorView(season: season, application: nil)
        }
        .sheet(item: $applicationToEdit) { application in
            if let season = application.season {
                FertilizerApplicationEditorView(season: season, application: application)
            }
        }
        .confirmationDialog(
            "Delete \(seasonToDelete?.name ?? "this season")?",
            isPresented: isConfirmingDelete,
            presenting: seasonToDelete
        ) { season in
            Button("Delete Season", role: .destructive) {
                modelContext.delete(season)
                try? modelContext.save()
            }
        } message: { _ in
            Text("The fertilizer recorded for it is deleted too.")
        }
    }

    private var currentSeasonID: PersistentIdentifier? {
        field.currentSeason?.persistentModelID
    }

    // MARK: - Season card

    private func seasonCard(_ season: Season, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(season.name)
                        .font(.body.weight(.semibold))
                    Text(summary(of: season))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Text("Current")
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(Color.green.opacity(0.18), in: Capsule())
                }
                if canEdit {
                    Menu {
                        Button("Edit Season") {
                            seasonToEdit = season
                        }
                        Button("Delete Season", role: .destructive) {
                            seasonToDelete = season
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Change season")
                    }
                }
            }

            if isCurrent && !doses.isEmpty {
                progress(for: season)
            }

            if !season.applications.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(season.sortedApplications) { application in
                        applicationRow(application)
                    }
                }
            }

            if canEdit {
                Button {
                    seasonForNewApplication = season
                } label: {
                    Label("Fertilizer Put On", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    /// "Inpari 32 · transplanted 12 Nov 2026 · 5.8 t/ha"
    private func summary(of season: Season) -> String {
        var parts: [String] = []
        if !season.variety.isEmpty {
            parts.append(season.variety)
        }
        if let planted = season.plantedOn {
            parts.append("transplanted \(planted.formatted(date: .abbreviated, time: .omitted))")
        } else {
            parts.append("transplanting date not entered")
        }
        if let harvested = season.harvestedOn {
            parts.append("harvested \(harvested.formatted(date: .abbreviated, time: .omitted))")
        }
        if let yield = season.yieldTonnesPerHectare {
            parts.append("\(yield.formatted(.number.precision(.fractionLength(0...2)))) t/ha")
        }
        return parts.joined(separator: " · ")
    }

    private func progress(for season: Season) -> some View {
        let rows = FertilizerProgress.compare(doses: doses, applied: season.appliedAmounts)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Put on against the plan")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.fertilizer) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.fertilizer.name)
                        Spacer()
                        Text(progressLabel(row))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if let share = row.shareApplied {
                        ProgressView(value: min(share, 1))
                    }
                }
                .font(.callout)
            }
        }
    }

    /// "90 of 180 kg", or "90 kg so far" when the field's area is not known.
    private func progressLabel(_ row: FertilizerProgress) -> String {
        let applied = row.appliedKilograms.formatted(.number.precision(.fractionLength(0...1)))
        guard let planned = row.plannedKilograms else {
            return "\(applied) kg so far · enter the field's area to compare"
        }
        let plannedText = planned.formatted(.number.precision(.fractionLength(0...1)))
        var label = "\(applied) of \(plannedText) kg"
        if let share = row.shareApplied, share > 1.1 {
            label += " · more than planned"
        }
        return label
    }

    private func applicationRow(_ application: FertilizerApplication) -> some View {
        HStack {
            Text(application.appliedOn, format: .dateTime.day().month())
                .frame(width: 60, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(application.label)
            Spacer()
            Text("\(application.kilograms, format: .number.precision(.fractionLength(0...1))) kg")
                .monospacedDigit()
        }
        .font(.callout)
        .contentShape(Rectangle())
        .contextMenu {
            if canEdit {
                Button("Edit") {
                    applicationToEdit = application
                }
                Button("Delete", role: .destructive) {
                    modelContext.delete(application)
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Yield

    private struct YieldPoint: Identifiable {
        var id: PersistentIdentifier
        var season: String
        var startedAt: Date
        var tonnesPerHectare: Double
    }

    private var yieldPoints: [YieldPoint] {
        field.seasons
            .compactMap { season in
                season.yieldTonnesPerHectare.map {
                    YieldPoint(
                        id: season.persistentModelID,
                        season: season.name,
                        startedAt: season.startedAt,
                        tonnesPerHectare: $0
                    )
                }
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    @ViewBuilder
    private var yieldChart: some View {
        if yieldPoints.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Yield by Season")
                    .font(.subheadline.weight(.semibold))
                Chart {
                    RuleMark(y: .value("Guide low", HarvestYield.guideRangeTonnesPerHectare.lowerBound))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                    RuleMark(y: .value("Guide high", HarvestYield.guideRangeTonnesPerHectare.upperBound))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                    ForEach(yieldPoints) { point in
                        BarMark(
                            x: .value("Season", point.season),
                            y: .value("Tonnes a hectare", point.tonnesPerHectare)
                        )
                    }
                }
                .chartYAxisLabel("t/ha")
                .frame(height: 160)
                Text("The dashed lines mark the 5 to 7 t/ha the fertilizer doses are written for.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { seasonToDelete != nil },
            set: { isShowing in
                if !isShowing { seasonToDelete = nil }
            }
        )
    }
}
