import SwiftUI

/// What a test found: the score, how many protists, nematodes and rotifers (and anything else),
/// and what kinds each is made of. Upload sends it to the records, with the picture of each
/// organism the run counted; Retest scraps it.
///
/// `isNew` is a result just taken: it says "Saved in the archive" for three seconds and offers
/// Retest. One opened from the archive offers Upload only, because scrapping a kept result is
/// not something a stray tap should do. The advice is on the farm's page on the helper side.
struct ScientistResultScreen: View {
    let sweep: SavedSweep
    var isNew = false
    /// Called after the scrapped test's folder is gone, to start the test again. nil hides Retest.
    var onRetest: (() -> Void)?

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected = SoilLifeGroup.protists
    @State private var showsSaved = false
    @State private var showsWhy = false
    @State private var isConfirmingRetest = false
    @State private var upload = Upload.ready
    /// The organism pictures Upload sends, and how many it has sent so far.
    @State private var pictures: [OrganismPicture] = []
    @State private var picturesSent = 0

    private enum Upload: Equatable {
        case ready, sending, sent
        case failed(String)
    }

    private let result: SoilResult?
    private let estimate: SoilHealthEstimate?
    private let kinds: [SoilLifeGroup: [SoilLifeGroup.Kind]]

    init(sweep: SavedSweep, isNew: Bool = false, onRetest: (() -> Void)? = nil) {
        self.sweep = sweep
        self.isNew = isNew
        self.onRetest = isNew ? onRetest : nil
        let result = try? SoilResult(sweep: sweep)
        self.result = result
        estimate = result.map { PlaceholderSoilHealthEstimator().estimate($0) }
        kinds = SoilLifeGroup.summarize(result?.countsByClass ?? [:])
    }

    private func count(_ group: SoilLifeGroup) -> Int {
        kinds[group]?.map(\.count).reduce(0, +) ?? 0
    }

    /// Other only appears when something landed there.
    private var groups: [SoilLifeGroup] {
        SoilLifeGroup.allCases.filter { $0 != .other || count($0) > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if let estimate { gauge(estimate) }
                    detected
                }
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            footer
        }
        .auraBackground()
        .navigationBarBackButtonHidden()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward").font(.title3).frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(.leading, 22)
            .accessibilityLabel("Back")
        }
        .task {
            let sweep = sweep
            pictures = await Task.detached { OrganismPictures.of(sweep) }.value
        }
        .task {
            guard isNew else { return }
            showsSaved = true
            try? await Task.sleep(for: .seconds(3))
            withAnimation { showsSaved = false }
        }
        .confirmationDialog(
            "Scrap this result?", isPresented: $isConfirmingRetest, titleVisibility: .visible
        ) {
            Button("Scrap and retest", role: .destructive) { scrapAndRetest() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It is deleted from the archive and a new test is started in its place.")
        }
    }

    // MARK: Sections

    private var header: some View {
        let details = sweep.manifest?.details
        let found = store.farms.plot(for: details)
        return VStack(spacing: 2) {
            Text(
                found.map { "\($0.farm.farmerName)・\($0.farm.title(of: $0.plot))" }
                    ?? details?.sampleID ?? sweep.name
            )
            .font(.headline)
            Text(
                (details?.recordedAt ?? sweep.recordedAt)
                    .formatted(.dateTime.day().month(.abbreviated).year())
            )
            .font(.callout.weight(.medium)).foregroundStyle(.secondary)
            // The pill takes its space while it is there and gives it back after three seconds.
            if showsSaved {
                Label("Saved in the archive", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.aura.opacity(0.29), in: Capsule())
                    .overlay(Capsule().stroke(Color.aura))
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 64)
    }

    private func gauge(_ estimate: SoilHealthEstimate) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(.primary.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: Double(estimate.score ?? 0) / 100)
                    .stroke(Color.aura, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(estimate.score.map(String.init) ?? "–")
                        .font(.system(size: 60, weight: .heavy).width(.condensed))
                    Text(estimate.level.shortTitle).font(.footnote)
                }
            }
            .frame(width: 145, height: 145)
            .padding(.top, 36)
            .accessibilityElement(children: .combine)

            Button { showsWhy = true } label: {
                Label("\(estimate.confidence.label) confidence", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon).font(.footnote).foregroundStyle(.secondary)
            }
            .popover(isPresented: $showsWhy) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(estimate.reasons, id: \.self) { Text("• " + $0) }
                    Text(estimate.followUp).foregroundStyle(.secondary)
                }
                .font(.callout).padding().frame(maxWidth: 320)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var detected: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("We detect").font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
            // The chosen card stands taller and higher than the others, which sit lower and fainter.
            HStack(alignment: .top, spacing: 8) {
                ForEach(groups) { group in groupCard(group) }
            }
            detail(of: selected)
        }
        .padding(.horizontal, 24).padding(.top, 44)
    }

    private func groupCard(_ group: SoilLifeGroup) -> some View {
        let isOn = selected == group
        return Button { withAnimation(.snappy) { selected = group } } label: {
            VStack(spacing: 0) {
                Group {
                    if let name = group.imageName {
                        Image(name).resizable().scaledToFit()
                    } else {
                        Image(systemName: "questionmark").resizable().scaledToFit().padding(4)
                    }
                }
                .frame(width: isOn ? 32 : 24, height: isOn ? 32 : 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text("\(count(group))").font(.system(size: isOn ? 36 : 30, weight: .semibold))
                Text(group.title).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: isOn ? 112 : 96)
            .background(
                isOn ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.18), lineWidth: 1)
                }
            }
            .opacity(isOn ? 1 : 0.55)
            // Unchosen cards sit lower, so the chosen one reads as lifted.
            .padding(.top, isOn ? 0 : 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.title), \(count(group))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The selected group's kinds, each with the organisms behind it and what they are.
    private func detail(of group: SoilLifeGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rows = kinds[group] {
                ForEach(rows) { kind in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(kind.name) : \(kind.count)")
                        ForEach(kind.organisms) { organism in
                            Text(
                                organism.description.isEmpty
                                    ? "\(organism.name) · \(organism.count)"
                                    : "\(organism.name) · \(organism.count) — \(organism.description)"
                            )
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No \(group.title.lowercased()) detected in this test.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Actions

    private var footer: some View {
        VStack(spacing: 12) {
            switch upload {
            case .ready, .failed:
                Button { Task { await send() } } label: {
                    Label(
                        upload == .ready ? "Upload" : "Try again",
                        systemImage: "icloud.and.arrow.up"
                    )
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(.large).tint(.aura).foregroundStyle(Color.auraOnAccent)
                if !pictures.isEmpty {
                    Text(
                        pictures.count == 1
                            ? "With 1 organism picture" : "With \(pictures.count) organism pictures"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                if case .failed(let problem) = upload {
                    Text(problem).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            case .sending:
                ProgressView(
                    pictures.isEmpty
                        ? "Uploading" : "Uploading · \(picturesSent) of \(pictures.count) pictures")
            case .sent:
                Label("Uploaded", systemImage: "checkmark.circle.fill").foregroundStyle(Color.aura)
            }
            if onRetest != nil, upload != .sent {
                Button("Retest") { isConfirmingRetest = true }
                    .foregroundStyle(Color.aura).disabled(upload == .sending)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    /// Builds the report off the main thread, because it can carry the panorama, then sends it.
    /// The test is already saved on the phone, so a failure costs the sending and not the test.
    private func send() async {
        upload = .sending
        picturesSent = 0
        let sweep = sweep
        do {
            let (report, found) = try await Task.detached(priority: .userInitiated) {
                (try SoilReportExporter.report(for: sweep), OrganismPictures.of(sweep))
            }.value
            pictures = found
            guard let uploader = SoilResultUploader() else {
                throw SoilResultUploader.Failure.notConfigured
            }
            try await uploader.upload(report, pictures: found) { picturesSent = $0 }
            upload = .sent
        } catch {
            upload = .failed(error.localizedDescription)
        }
    }

    private func scrapAndRetest() {
        do {
            try FileManager.default.removeItem(at: sweep.url)
            onRetest?()
        } catch {
            upload = .failed("The test could not be deleted: \(error.localizedDescription)")
        }
    }
}

extension SoilHealthEstimate.Level {
    /// One word under the score.
    var shortTitle: String {
        switch self {
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        case .tooFewToSay: "Too few"
        case .notCounted: "Not counted"
        }
    }
}
