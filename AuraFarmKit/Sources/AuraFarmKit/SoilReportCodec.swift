import Foundation

/// Reads and writes soil reports as JSON.
///
/// Both apps go through here, so the date format and key order are the same on each side.
public enum SoilReportCodec {
    public enum Failure: Error, Equatable, LocalizedError {
        /// The file is a soil report from a newer field app than this build can read.
        case newerSchemaVersion(Int)
        /// The file is not a soil report, or it is damaged.
        case notASoilReport

        public var errorDescription: String? {
            switch self {
            case .newerSchemaVersion:
                return "This report is from a newer Aura Farm. Update this app to open it."
            case .notASoilReport:
                return "This file is not an Aura Farm soil report, or it is damaged."
            }
        }
    }

    public static func encode(_ report: SoilReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    public static func decode(_ data: Data) throws -> SoilReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // The version is read on its own first, so a report from a newer app is named as
        // such instead of failing as damaged on whatever field it added.
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw Failure.notASoilReport
        }
        guard header.schemaVersion <= SoilReport.currentSchemaVersion else {
            throw Failure.newerSchemaVersion(header.schemaVersion)
        }
        do {
            return try decoder.decode(SoilReport.self, from: data)
        } catch {
            throw Failure.notASoilReport
        }
    }

    private struct Header: Decodable {
        var schemaVersion: Int
    }
}
