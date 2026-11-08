import AuraFarmKit
import Foundation
import SwiftData

/// One soil test received from the field app, filed under a field or waiting in the inbox.
///
/// It holds what the sweep counted and how, never a verdict on the soil. The counts are raw
/// and only comparable between tests prepared the same way.
@Model
final class SoilTest {
    /// The report's ID. The field app gives every send of one sweep the same ID, so a repeat
    /// is recognised and skipped.
    @Attribute(.unique) var reportID: UUID
    /// Identifier written on the sample bag or tube.
    var sampleID: String
    var recordedAt: Date
    var importedAt: Date
    /// Which microscope field of view of the sample. Not a farm field.
    var microscopeField: Int
    /// `flooded` or `drained`, as the helper entered it.
    var moisture: String
    var gramsOfSoil: Double? = nil
    var millilitresScanned: Double? = nil
    var millilitresOfWater: Double? = nil
    /// How the slide was made, in words. Empty for reports from before it was recorded.
    var preparation: String = ""
    var frameCount: Int
    /// True when the sweep stopped at its size limit instead of finishing its path.
    var stoppedEarly: Bool
    var detectorModel: String
    var fieldAppVersion: String
    /// The sweep's frames joined into one picture of the slide, when the phone made one.
    @Attribute(.externalStorage) var panoramaJPEG: Data? = nil
    var notes: String = ""
    /// nil while the test is in the inbox.
    var field: Field? = nil

    @Relationship(deleteRule: .cascade, inverse: \OrganismCount.soilTest)
    var organismCounts: [OrganismCount] = []

    /// A soil test from a report. Its organism counts are added by the importer, once the
    /// test is in a model context.
    init(report: SoilReport, importedAt: Date = .now) {
        self.reportID = report.id
        self.sampleID = report.sample.sampleID
        self.recordedAt = report.sample.recordedAt
        self.importedAt = importedAt
        self.microscopeField = report.sample.microscopeField
        self.moisture = report.sample.moisture
        self.gramsOfSoil = report.sample.gramsOfSoil
        self.millilitresScanned = report.sample.millilitresScanned
        self.millilitresOfWater = report.sample.millilitresOfWater
        self.preparation = report.sample.preparation ?? ""
        self.frameCount = report.capture.frameCount
        self.stoppedEarly = report.capture.stoppedEarly
        self.detectorModel = report.capture.detectorModel
        self.fieldAppVersion = report.capture.appVersion
        self.panoramaJPEG = report.panoramaJPEG
    }

    /// Every organism counted, across all groups.
    var totalCount: Int {
        organismCounts.reduce(0) { $0 + $1.count }
    }

    /// Most counted first, then by name.
    var sortedCounts: [OrganismCount] {
        organismCounts.sorted { $0.count != $1.count ? $0.count > $1.count : $0.taxon < $1.taxon }
    }

    var moistureLabel: String {
        moisture.capitalized
    }

    /// "Farm · Field", or "Unassigned" while the test is in the inbox.
    var placeLabel: String {
        guard let field else { return "Unassigned" }
        guard let farm = field.farm else { return field.name }
        return "\(farm.name) · \(field.name)"
    }
}
