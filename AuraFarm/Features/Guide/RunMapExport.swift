import SwiftUI

/// The run map as a picture for sharing: the map, the legend and a title on a dark card.
struct RunMapSnapshot: View {
    var record: GuideRunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(record.title): \(record.totalCount) organisms")
                .font(.title3.bold())
                .foregroundStyle(.white)
            RunMapView(content: RunMapContent(record: record))
            LifeLegendView(counts: record.countsByLabel).foregroundStyle(.white)
        }
        .padding(20)
        .frame(width: 800, height: 760)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }
}

/// Draws the map to a PNG.
@MainActor
enum RunMapExport {
    static func pngData(for record: GuideRunRecord) -> Data? {
        let renderer = ImageRenderer(content: RunMapSnapshot(record: record))
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }
}
