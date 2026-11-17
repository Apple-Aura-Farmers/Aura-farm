#if DEBUG
    import SwiftUI

    /// The helper's count while the run is counting: the map's total, and a count per type if it
    /// fits. `ViewThatFits` picks the first of: the total and every type on one line; the total and
    /// the top two types with "+N more"; the total alone. Types with no count are left out.
    struct HelperCountChip: View {
        var info: LiveCountInfo

        var body: some View {
            if info.isActive {
                ViewThatFits(in: .horizontal) {
                    chip(LiveCountInfo.line(info.labels))
                    chip(LiveCountInfo.line(info.labels, limit: 2))
                    chip("")
                }
            }
        }

        private func chip(_ types: String) -> some View {
            HStack(spacing: 6) {
                Text(LiveCountInfo.organisms(info.total)).bold()
                if !types.isEmpty { Text("·").foregroundStyle(.white.opacity(0.6)) }
                if !types.isEmpty { Text(types) }
            }
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.7), in: Capsule())
            .frame(maxWidth: .infinity)
        }
    }

    /// The detector's boxes over the picture: green counted, grey seen once, blue a repeat (already
    /// on the map). `polygon` turns a box in frame pixels into points of the displayed space, so
    /// the boxes go through the same centring and straightening as the picture.
    struct DetectionBoxes: View {
        var info: LiveCountInfo
        var polygon: (CGRect) -> [CGPoint]

        static func colour(_ status: LiveOrganismCounter.BoxStatus) -> Color {
            switch status {
            case .counted: .green
            case .seenOnce: .gray
            case .repeatOnMap: .blue
            }
        }

        var body: some View {
            Canvas { context, _ in
                for box in info.boxes {
                    let points = polygon(box.rect)
                    guard let first = points.first else { continue }
                    var path = Path()
                    path.addLines(points)
                    path.closeSubpath()
                    let colour = Self.colour(box.status)
                    context.stroke(path, with: .color(colour), lineWidth: 2)
                    let caption = Text(
                        "\(box.id) \(OrganismDisplayName.label(box.label)) \(Int(box.confidence * 100))%"
                    )
                    .font(.caption2.bold())
                    .foregroundStyle(colour)
                    context.draw(caption, at: CGPoint(x: first.x, y: first.y - 8), anchor: .bottomLeading)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// A row per type with the map's count and the tally's, and the frames counted and skipped.
    /// The two differ where a column re-found an organism the map already had.
    struct DetectionPanel: View {
        var info: LiveCountInfo

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Detections").font(.caption.bold())
                if let problem = info.problem {
                    Text(problem).foregroundStyle(.red)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("Type").foregroundStyle(.secondary)
                        Text("Map").foregroundStyle(.secondary)
                        Text("Tally").foregroundStyle(.secondary)
                    }
                    ForEach(info.labels) { row in
                        GridRow {
                            Text(row.display)
                            Text("\(row.map)")
                            Text("\(row.tally)")
                        }
                    }
                    GridRow {
                        Text("Total").bold()
                        Text("\(info.total)").bold()
                        Text("\(info.tallyTotal)").bold()
                    }
                }
                Text(
                    "Model \(DetectorModel(rawValue: info.detectorModel)?.displayName ?? info.detectorModel)"
                        + (info.loadMilliseconds.map { " · opened in \(Int($0)) ms" } ?? "")
                        + (info.isLoadingModel ? " · opening…" : ""))
                Text("Dropped: disc \(info.discDrops) · too big \(info.bigDrops)")
                Text("Frames counted \(info.framesCounted) · skipped \(skipped)")
            }
            .font(.footnote.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }

        private var skipped: String {
            let total = info.framesSkipped.values.reduce(0, +)
            guard total > 0 else { return "0" }
            let parts = info.framesSkipped.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }
            return "\(total) (\(parts.joined(separator: ", ")))"
        }
    }

    /// "Ending after this column" with the way to take it back.
    struct EndingBanner: View {
        var onKeepGoing: () -> Void = {}

        var body: some View {
            HStack {
                Text("Ending after this column").font(.subheadline.bold())
                Spacer()
                Button("Keep going", action: onKeepGoing).buttonStyle(.bordered)
            }
            .padding(10)
            .background(.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// The card shown when the route finishes, for any reason.
    struct RunSummaryCard: View {
        var record: GuideRunRecord
        var shareItems: [URL]
        var onDone: () -> Void = {}

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(record.title).font(.title2.bold())
                Text(LiveCountInfo.organisms(record.totalCount)).font(.title3)
                let perType = record.countsByLabel.sorted { $0.value > $1.value }
                if !perType.isEmpty {
                    Text(
                        perType.map { "\(OrganismDisplayName.label($0.key)) \($0.value)" }.joined(
                            separator: " · ")
                    )
                    .font(.subheadline)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Columns", "\(record.columns)")
                    row("Coverage", record.coverageText)
                    row(
                        "Time",
                        String(
                            format: "%d:%02d", Int(record.elapsedSeconds) / 60,
                            Int(record.elapsedSeconds) % 60))
                    row("Spots ticked", "\(record.spotsTicked)")
                    row("Missed spots", "\(record.missedSpots)")
                    row("Seconds per spot", record.secondsPerSpot.map { String(format: "%.1f", $0) } ?? "-")
                }
                .font(.subheadline.monospacedDigit())
                HStack {
                    if shareItems.isEmpty {
                        Button("Share run") {}.disabled(true)
                    } else {
                        ShareLink("Share run", items: shareItems)
                    }
                    Spacer()
                    Button("Done", action: onDone).buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }

        private func row(_ name: String, _ value: String) -> some View {
            GridRow {
                Text(name).foregroundStyle(.secondary)
                Text(value)
            }
        }
    }

    // MARK: - Previews

    private let previewLabels: [LiveCountInfo.LabelCount] = [
        .init(label: "Volvox", map: 7, tally: 9), .init(label: "Nematode", map: 5, tally: 5),
        .init(label: "Euglenoid", map: 2, tally: 3),
    ]

    private func previewInfo(boxes: [LiveCountInfo.Box] = []) -> LiveCountInfo {
        LiveCountInfo(
            isActive: true, total: 14, tallyTotal: 17, labels: previewLabels, boxes: boxes,
            frameSize: CGSize(width: 1280, height: 720), framesCounted: 412,
            framesSkipped: ["too_fast": 38, "not_tracking": 11])
    }

    #Preview("Count chip: wide, medium, narrow") {
        VStack(spacing: 12) {
            ForEach([380.0, 250.0, 150.0], id: \.self) { width in
                HelperCountChip(info: previewInfo()).frame(width: width)
            }
        }
        .padding()
        .background(.gray)
    }

    #Preview("Count chip with a long type name: wide, medium, narrow") {
        let info = LiveCountInfo(
            isActive: true, total: 9,
            labels: [
                .init(label: "Didinium_Phacus_Collodictyon", map: 4, tally: 4),
                .init(label: "Paramecium_Coleps", map: 3, tally: 3),
                .init(label: "Stentor", map: 2, tally: 2),
            ])
        VStack(spacing: 12) {
            ForEach([390.0, 300.0, 150.0], id: \.self) { width in
                HelperCountChip(info: info).frame(width: width)
            }
        }
        .padding()
        .background(.gray)
    }

    #Preview("Show detections: green, grey, blue and the panel") {
        let boxes: [LiveCountInfo.Box] = [
            .init(
                id: 3, label: "Volvox", confidence: 0.91,
                rect: CGRect(x: 100, y: 120, width: 140, height: 140), status: .counted),
            .init(
                id: 4, label: "Nematode", confidence: 0.42,
                rect: CGRect(x: 520, y: 300, width: 200, height: 90), status: .seenOnce),
            .init(
                id: 1, label: "Volvox", confidence: 0.77,
                rect: CGRect(x: 800, y: 80, width: 120, height: 120), status: .repeatOnMap),
        ]
        VStack {
            ZStack {
                Color.brown.opacity(0.5)
                DetectionBoxes(info: previewInfo(boxes: boxes)) { rect in
                    let scale = 0.3
                    return [
                        CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                        CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                    ].map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                }
            }
            .frame(width: 384, height: 216)
            DetectionPanel(info: previewInfo(boxes: boxes))
        }
    }

    #Preview("End run: banner") {
        EndingBanner().padding()
    }

    #Preview("End run: dialog") {
        EndRunDialogPreview()
    }

    private struct EndRunDialogPreview: View {
        @State private var isShown = true
        var body: some View {
            Button("End run") { isShown = true }
                .confirmationDialog("End run", isPresented: $isShown, titleVisibility: .visible) {
                    Button("End now", role: .destructive) {}
                    Button("End after this column") {}
                    Button("Cancel", role: .cancel) {}
                }
        }
    }

    private func previewRecord(_ reason: SweepFinishReason, share: Double?) -> GuideRunRecord {
        GuideRunRecord(
            started: .now, ended: .now, finishReason: reason, spotMode: "brief_touch",
            coverageStep: 0.8, columns: 4, spotsTicked: 31, missedSpots: 3, elapsedSeconds: 312,
            secondsPerSpot: 10.1, coverageShare: share,
            countsByLabel: ["Volvox": 7, "Nematode": 5, "Euglenoid": 2],
            tallyCountsByLabel: ["Volvox": 9, "Nematode": 5, "Euglenoid": 3], totalCount: 14,
            minimumConfidence: 0.3, cropToEyepiece: false, classNames: [], framesCounted: 412,
            framesSkippedByReason: ["too_fast": 38])
    }

    #Preview("Summary: ended early") {
        RunSummaryCard(record: previewRecord(.endedByHelper, share: nil), shareItems: [])
    }

    #Preview("Summary: reached the right edge") {
        RunSummaryCard(record: previewRecord(.rightEdge, share: 0.92), shareItems: [])
    }

    #Preview("Model chip and Camera pickers") {
        Form {
            Picker("Model chip", selection: .constant(DetectorUnits.neuralEngine.rawValue)) {
                ForEach(DetectorUnits.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Picker("Camera", selection: .constant(CameraRate.fps20.rawValue)) {
                ForEach(CameraRate.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text("20 fps, exposure capped at 1/30 s.").font(.caption).foregroundStyle(.secondary)
            Picker("Camera", selection: .constant(CameraRate.fps20.rawValue)) {
                ForEach(CameraRate.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .disabled(true)
            Text("The model, chip and camera can change before Mark start or after a finish.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
#endif
