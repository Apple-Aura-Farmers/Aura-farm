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
    /// The model the counts came from ("v1" or "v2"; `DetectorModel.rawValue`) and the boxes the
    /// guards dropped as the eyepiece disc and as too big. Earlier records have none: V1, 0, 0.
    var detectorModel = DetectorModel.v1.rawValue
    var discDrops = 0
    var bigDrops = 0
    /// The hardware the model ran on (`DetectorUnits.rawValue`: "ne" or "gpu"). Earlier records ran
    /// on the graphics chip.
    var detectorUnits = DetectorUnits.graphics.rawValue
    /// How the right edge was found: "line", "empty" (the view went empty ahead) or "predicted"
    /// (the square cover slip's); empty when it was not found. Earlier records have none.
    var rightEdgeSource = ""
    /// How far the first and last columns sat inside the left and right edges, in fields (the
    /// confirmed eyepiece circle's radius plus a margin); nil when the circle was not known and
    /// for earlier records.
    var sideInsetFields: Double?
    /// The map of the run, in fields in the trail's space, so it can be redrawn from the record
    /// alone: the organisms the helper's count includes, the path (at most
    /// `RunMapContent.maxPathPoints` points), the edges, and how that space turns onto the screen
    /// (`ScreenMapping.rawValue` and the mirror). Earlier records have none.
    var organisms: [RunMapOrganism] = []
    var path: [RunMapPoint] = []
    var edges: [RunMapEdge] = []
    var mapMapping = ScreenMapping.asIs.rawValue
    var mapMirrored = false
    /// Seconds spent in each heat mode (`HeatMode.csvName`: "normal", "cool_down", "too_hot").
    /// Earlier records have none.
    var heatSeconds: [String: Double] = [:]
    /// The cap on the model's runs a second in force (5), or nil when the lab turned it off.
    /// Earlier records have none.
    var modelRateCap: Double?
    /// The lens video saved with this run (a file in the sweep's folder) and where "Start scan" falls
    /// in it, in seconds. Earlier records have none.
    var lensVideoFile: String?
    var lensVideoScanStartSeconds: Double?

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

extension GuideRunRecord {
    /// Records saved before the detector model and the guard drops were added still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            started: try c.decode(Date.self, forKey: .started),
            ended: try c.decode(Date.self, forKey: .ended),
            finishReason: try c.decode(SweepFinishReason.self, forKey: .finishReason),
            spotMode: try c.decode(String.self, forKey: .spotMode),
            coverageStep: try c.decode(Double.self, forKey: .coverageStep),
            columns: try c.decode(Int.self, forKey: .columns),
            spotsTicked: try c.decode(Int.self, forKey: .spotsTicked),
            missedSpots: try c.decode(Int.self, forKey: .missedSpots),
            elapsedSeconds: try c.decode(Double.self, forKey: .elapsedSeconds),
            secondsPerSpot: try c.decodeIfPresent(Double.self, forKey: .secondsPerSpot),
            coverageShare: try c.decodeIfPresent(Double.self, forKey: .coverageShare),
            countsByLabel: try c.decode([String: Int].self, forKey: .countsByLabel),
            tallyCountsByLabel: try c.decode([String: Int].self, forKey: .tallyCountsByLabel),
            totalCount: try c.decode(Int.self, forKey: .totalCount),
            minimumConfidence: try c.decode(Double.self, forKey: .minimumConfidence),
            cropToEyepiece: try c.decode(Bool.self, forKey: .cropToEyepiece),
            classNames: try c.decode([String].self, forKey: .classNames),
            framesCounted: try c.decode(Int.self, forKey: .framesCounted),
            framesSkippedByReason: try c.decode([String: Int].self, forKey: .framesSkippedByReason),
            detectorModel: try c.decodeIfPresent(String.self, forKey: .detectorModel)
                ?? DetectorModel.v1.rawValue,
            discDrops: try c.decodeIfPresent(Int.self, forKey: .discDrops) ?? 0,
            bigDrops: try c.decodeIfPresent(Int.self, forKey: .bigDrops) ?? 0,
            detectorUnits: try c.decodeIfPresent(String.self, forKey: .detectorUnits)
                ?? DetectorUnits.graphics.rawValue,
            rightEdgeSource: try c.decodeIfPresent(String.self, forKey: .rightEdgeSource) ?? "",
            sideInsetFields: try c.decodeIfPresent(Double.self, forKey: .sideInsetFields),
            organisms: try c.decodeIfPresent([RunMapOrganism].self, forKey: .organisms) ?? [],
            path: try c.decodeIfPresent([RunMapPoint].self, forKey: .path) ?? [],
            edges: try c.decodeIfPresent([RunMapEdge].self, forKey: .edges) ?? [],
            mapMapping: try c.decodeIfPresent(String.self, forKey: .mapMapping)
                ?? ScreenMapping.asIs.rawValue,
            mapMirrored: try c.decodeIfPresent(Bool.self, forKey: .mapMirrored) ?? false,
            heatSeconds: try c.decodeIfPresent([String: Double].self, forKey: .heatSeconds) ?? [:],
            modelRateCap: try c.decodeIfPresent(Double.self, forKey: .modelRateCap))
        lensVideoFile = try c.decodeIfPresent(String.self, forKey: .lensVideoFile)
        lensVideoScanStartSeconds = try c.decodeIfPresent(
            Double.self, forKey: .lensVideoScanStartSeconds)
    }
}
