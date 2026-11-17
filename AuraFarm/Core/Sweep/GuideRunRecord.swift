import Foundation

/// What one guided run came to, saved as JSON when the route finishes and shown on the summary
/// card. Pure data.
struct GuideRunRecord: Codable, Equatable {
    var started: Date
    var ended: Date
    var finishReason: SweepFinishReason
    /// "brief_touch" or "hold_still".
    var spotMode: String
    /// Fields between columns: 0.8, 1.6 or 2.4.
    var coverageStep: Double
    var columns: Int
    var spotsTicked: Int
    var missedSpots: Int
    var elapsedSeconds: Double
    var secondsPerSpot: Double?
    /// Columns x coverage step over the left-to-right edge span, at most 1; nil unless both edges
    /// are known.
    var coverageShare: Double?
    /// The slide map's counts (what the helper saw) and the frame-to-frame tally's.
    var countsByLabel: [String: Int]
    var tallyCountsByLabel: [String: Int]
    var totalCount: Int
    var minimumConfidence: Double
    var cropToEyepiece: Bool
    var classNames: [String]
    var framesCounted: Int
    var framesSkippedByReason: [String: Int]

    /// The share of the edge span the columns reach; nil unless the span is known and positive.
    static func coverageShare(columns: Int, step: Double, edgeSpanFields: Double?) -> Double? {
        guard let span = edgeSpanFields, span > 0 else { return nil }
        return min(Double(columns) * step / span, 1)
    }

    /// The summary card's title for how the route ended.
    static func title(for reason: SweepFinishReason) -> String {
        switch reason {
        case .endedByHelper: "Ended early"
        case .stageLimit: "Stage limit"
        case .rightEdge: "Reached the right edge"
        case .sampleFinished, .storageFull: "Finished"
        }
    }

    var title: String { Self.title(for: finishReason) }

    /// "62%", or "unknown" when an edge was not found.
    var coverageText: String {
        coverageShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "unknown"
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
