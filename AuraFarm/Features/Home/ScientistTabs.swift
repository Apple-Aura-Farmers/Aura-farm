import SwiftUI

/// What the scientist sees once tests are done: each one under the plot it was taken on, newest
/// first, with Results to open it.
struct ScientistArchiveView: View {
    @Environment(FarmStore.self) private var store
    @State private var sweeps: [SavedSweep] = []
    @State private var opened: SavedSweep?

    /// Counted tests only: a sweep the detector never counted has no result to open.
    private var tests: [SavedSweep] { sweeps.filter { $0.manifest?.organismCounts != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if tests.isEmpty {
                    ScientistEmptyState(
                        symbol: "archivebox", title: "No Archives",
                        message: "No completed results for viewing. Finish analyzing a sample to view.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(tests) { sweep in
                            let plot = plot(of: sweep)
                            ScientistRow(
                                corners: plot?.plot.corners ?? [],
                                title: plot.map { "\($0.farm.farmerName) ∙ \($0.farm.title(of: $0.plot))" }
                                    ?? sweep.manifest?.details.sampleID ?? sweep.name,
                                subtitle: scientistAgo(sweep.recordedAt), isAlert: false,
                                button: "Results"
                            ) { opened = sweep }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .auraBackground()
            .navigationTitle("Archives")
            .sheet(item: $opened) { sweep in
                NavigationStack { SoilResultScreen(sweep: sweep) }
            }
            .onAppear { sweeps = SweepLibrary.sweeps() }
        }
    }

    private func plot(of sweep: SavedSweep) -> (farm: Farm, plot: Plot)? {
        guard let details = sweep.manifest?.details,
            let farm = store.farms.first(where: { $0.id == details.farmID }),
            let plot = farm.plots.first(where: { $0.id == details.plotID }) ?? farm.plots.first
        else { return nil }
        return (farm, plot)
    }
}

extension Array where Element == SavedSweep {
    /// When the newest counted test of this plot was taken. A test with no plot was taken
    /// before plots could be chosen and counts for the farm's first (see `FarmTests`).
    func latestTest(of plot: Plot, in farm: Farm) -> Date? {
        let isFirst = farm.plots.first?.id == plot.id
        return filter { sweep in
            guard let details = sweep.manifest?.details, details.farmID == farm.id,
                sweep.manifest?.organismCounts != nil
            else { return false }
            return details.plotID == plot.id || (details.plotID == nil && isFirst)
        }
        .map(\.recordedAt).max()
    }
}

/// "1 min. ago" for something recent, "Nov 18" once it is older than a couple of days.
func scientistAgo(_ date: Date) -> String {
    if date > .now.addingTimeInterval(-2 * 86_400) {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// A plot's outline, who and which plot, when, and one button. A red dot marks an open alert.
struct ScientistRow: View {
    let corners: [GeoPoint]
    let title: String
    let subtitle: String
    let isAlert: Bool
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isAlert {
                Circle().fill(.red).frame(width: 12, height: 12).accessibilityLabel("Alert")
            }
            FarmOutlineThumbnail(corners: corners, size: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                Button(action: action) {
                    Text(button).padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(isAlert ? .aura : Color.primary.opacity(0.12))
                .foregroundStyle(isAlert ? Color.auraOnAccent : .aura)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color.auraRow, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.15)))
    }
}

/// The big symbol, bold title and one line of explanation the two screens show when empty.
struct ScientistEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 150))
                .foregroundStyle(.primary.opacity(0.86))
                .padding(.bottom, 12)
            Text(title).font(.system(size: 30, weight: .bold))
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 306)
        }
        .padding(.top, 120)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
