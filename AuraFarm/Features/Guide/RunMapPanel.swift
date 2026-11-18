import SwiftUI

/// The run map for the results screen: switches for the path, the organisms and the edges, the
/// map, and the legend. Tapping a legend row shows only that type. Drawn from a saved run
/// record alone.
struct RunMapPanel: View {
    var record: GuideRunRecord

    @State private var layers = RunMapLayers()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Path", isOn: $layers.path)
                Toggle("Organisms", isOn: $layers.organisms)
                Toggle("Edges", isOn: $layers.edges)
            }
            .toggleStyle(.button)
            .font(.subheadline)

            RunMapView(content: content)
                .frame(height: 280)

            LifeLegendView(
                counts: record.countsByLabel,
                highlight: Binding(get: { layers.onlyType }, set: { layers.onlyType = $0 }))
        }
        .padding(.vertical, 4)
    }

    /// The map's content with the switches applied.
    var content: RunMapContent {
        var content = RunMapContent(record: record)
        content.layers = layers
        return content
    }
}

#if DEBUG
    #Preview("Results screen map with switches") {
        List {
            Section("Run map") { RunMapPanel(record: .preview) }
        }
    }

    extension GuideRunRecord {
        /// A run along a snaking path, with a few organisms of three types.
        static var preview: GuideRunRecord {
            let labels = ["Volvox", "Nematode", "Euglenoid"]
            var record = GuideRunRecord(
                started: .now, ended: .now, finishReason: .sampleFinished, spotMode: "brief_touch",
                coverageStep: 1.6, columns: 9, spotsTicked: 40, missedSpots: 0, elapsedSeconds: 600,
                secondsPerSpot: 15, coverageShare: 0.5, countsByLabel: [:], tallyCountsByLabel: [:],
                totalCount: 0, minimumConfidence: 0.3, cropToEyepiece: true, classNames: labels,
                framesCounted: 100, framesSkippedByReason: [:])
            record.path = (0..<200).map {
                RunMapPoint(x: Double($0) / 14, y: 7 + 6 * sin(Double($0) / 9))
            }
            record.edges = [
                RunMapEdge(kind: "top", x1: 0, y1: 1, x2: 14, y2: 1),
                RunMapEdge(kind: "bottom", x1: 0, y1: 13, x2: 14, y2: 13),
            ]
            record.organisms = (0..<40).map {
                RunMapOrganism(
                    label: labels[$0 % 3], x: Double(($0 * 37) % 130) / 10,
                    y: 1.5 + Double(($0 * 53) % 110) / 10, column: $0 / 5 + 1, seconds: Double($0))
            }
            record.countsByLabel = Dictionary(grouping: record.organisms, by: \.label).mapValues(\.count)
            record.totalCount = record.organisms.count
            return record
        }
    }
#endif
