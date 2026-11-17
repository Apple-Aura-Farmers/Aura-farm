import AuraFarmKit
import SwiftUI

/// Publishing a finished test to the farm's records.
///
/// The report is built before the button appears, because a sweep the detector never counted
/// cannot become one at all and the reason is worth showing in its place.
struct PublishResultButton: View {
    let sweep: SavedSweep

    @State private var step = Step.preparing

    private enum Step {
        case preparing
        /// The sweep cannot become a report, with the reason to show.
        case cannotPublish(String)
        case ready(SoilReport)
    }

    var body: some View {
        Group {
            switch step {
            case .preparing:
                ProgressView("Preparing the result")
            case .cannotPublish(let reason):
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .ready(let report):
                PublishButton(title: "Publish result") {
                    guard let uploader = SoilResultUploader() else {
                        throw SoilResultUploader.Failure.notConfigured
                    }
                    try await uploader.upload(report)
                }
            }
        }
        .task(id: sweep.id) { await prepare() }
    }

    /// Builds the report off the main thread, because it can carry the panorama.
    private func prepare() async {
        guard case .preparing = step else { return }
        let sweep = sweep
        let built = await Task.detached(priority: .userInitiated) {
            Result { try SoilReportExporter.report(for: sweep) }
        }.value
        switch built {
        case .success(let report):
            step = .ready(report)
        case .failure(let error):
            step = .cannotPublish(error.localizedDescription)
        }
    }
}
