import SwiftUI

/// Every setting the lab hands the engine, in one value: what the lab's `onAppear` sets and
/// its `.onChange` handlers keep in step. The lab and the guided scan page both use it, so
/// the page can never drift from the lab. The keys and defaults are the lab's own.
struct LabSettings: Equatable {
    var mappingName = ScreenMapping.rotateRight.rawValue
    var mirrored = false
    var fieldRegionName = FieldRegionMode.auto.rawValue
    var hopAgreement = false
    var showsSees = false
    var guideDryRun = false
    var pausesOnMonitor = true
    var tracksSparse = true
    var fullCoverSlip = true
    var asksEdges = true
    /// Columns follow the cover slip's tilt once the left edge is confirmed with a known angle.
    var followsSlipTilt = true
    var showsLifeOnMap = true
    var coverSlipName = CoverSlipShape.square.rawValue
    var skipsAlignFocus = false
    var spotModeName = "briefTouch"
    var coverageStep = 0.8
    var countsOrganisms = true
    var showsDetections = false
    var cropsToEyepiece = true
    var confidence = OrganismDetector.defaultConfidence
    var detectorModelName = DetectorModel.v3.rawValue
    var detectorUnitsName = DetectorUnits.neuralEngine.rawValue
    var cameraRateName = CameraRate.fps20.rawValue
    /// Heat-adaptive mode (see `HeatPolicy`): on by default; the lab can turn it off to compare.
    var heatAdaptive = true
    /// Caps the model at `LiveCountThresholds.maxModelRunsPerSecond` runs a second. On by default.
    var modelRateCap = true
    /// Records the camera's frames to Documents/LensVideos. Off in the lab; the guided scan's own
    /// switch decides there.
    var recordsLensVideo = false

    /// What the guided scan uses in Release, where there is no lab to store settings: the
    /// lab's own defaults, except the three that are the chosen ones (rotate 90 degrees left,
    /// coverage 1.6, guide on). Everything else is the lab's default, so the two cannot drift.
    static let releaseDefaults: LabSettings = {
        var settings = LabSettings()
        settings.mappingName = ScreenMapping.rotateLeft.rawValue
        settings.coverageStep = GuidedScanCoverage.everySecondColumn.rawValue
        settings.guideDryRun = true
        return settings
    }()

    var mapping: ScreenMapping { ScreenMapping(rawValue: mappingName) ?? .asIs }
    var spotMode: SpotConfirmMode { spotModeName == "holdStill" ? .holdStill : .briefTouch }

    /// The guided scan page's settings: the lab's own, with the guide on, the operator's
    /// coverage, no detection boxes, and align and focus always done: a lab shortcut must not
    /// carry into a real test ("Skip setup" is the page's own). Nothing else differs.
    func forGuidedScan(coverage: Double, recordsVideo: Bool = false) -> LabSettings {
        var copy = self
        copy.recordsLensVideo = recordsVideo
        copy.guideDryRun = true
        copy.coverageStep = coverage
        copy.showsDetections = false
        copy.skipsAlignFocus = false
        // The real test never follows the lab's slider.
        copy.confidence = OrganismDetector.defaultConfidence
        return copy
    }

    /// The lab's `onAppear` sequence, in its order.
    func apply(to model: ScanEngine) {
        model.setSkipsAlignAndFocus(skipsAlignFocus)
        model.setPausesOnMonitor(pausesOnMonitor)
        model.setTracksSparse(tracksSparse)
        model.setFullCoverSlip(fullCoverSlip)
        model.setAsksEdges(asksEdges)
        model.setFollowsSlipTilt(followsSlipTilt)
        model.setShowsLifeOnMap(showsLifeOnMap)
        model.setCoverSlip(CoverSlipShape(rawValue: coverSlipName) ?? .square)
        model.setFieldRegion(FieldRegionMode(rawValue: fieldRegionName) ?? .auto)
        model.setMeasuresHopAgreement(hopAgreement)
        model.setShowsThumbnail(showsSees)
        model.setSpotMode(spotMode)
        model.setCoverageStep(coverageStep)
        model.setCountsOrganisms(countsOrganisms)
        model.setShowsDetections(showsDetections)
        model.setCropsToEyepiece(cropsToEyepiece)
        model.setMinimumConfidence(Float(confidence))
        model.setDetectorModel(DetectorModel(rawValue: detectorModelName) ?? .v3)
        model.setDetectorUnits(DetectorUnits(rawValue: detectorUnitsName) ?? .neuralEngine)
        model.setCameraRate(CameraRate(rawValue: cameraRateName) ?? .fps20)
        model.setGuideDryRun(guideDryRun)
        model.setScreenMapping(mapping, mirrored: mirrored)
        model.setHeatAdaptive(heatAdaptive)
        model.setModelRateCap(modelRateCap)
        model.setRecordsLensVideo(recordsLensVideo)
    }

    /// The lab's `.onChange` handlers: only what changed is handed over.
    func applyChanges(from old: LabSettings, to model: ScanEngine) {
        if fieldRegionName != old.fieldRegionName {
            model.setFieldRegion(FieldRegionMode(rawValue: fieldRegionName) ?? .auto)
        }
        if hopAgreement != old.hopAgreement { model.setMeasuresHopAgreement(hopAgreement) }
        if showsSees != old.showsSees { model.setShowsThumbnail(showsSees) }
        if guideDryRun != old.guideDryRun { model.setGuideDryRun(guideDryRun) }
        if skipsAlignFocus != old.skipsAlignFocus { model.setSkipsAlignAndFocus(skipsAlignFocus) }
        if pausesOnMonitor != old.pausesOnMonitor { model.setPausesOnMonitor(pausesOnMonitor) }
        if tracksSparse != old.tracksSparse { model.setTracksSparse(tracksSparse) }
        if fullCoverSlip != old.fullCoverSlip { model.setFullCoverSlip(fullCoverSlip) }
        if asksEdges != old.asksEdges { model.setAsksEdges(asksEdges) }
        if followsSlipTilt != old.followsSlipTilt { model.setFollowsSlipTilt(followsSlipTilt) }
        if showsLifeOnMap != old.showsLifeOnMap { model.setShowsLifeOnMap(showsLifeOnMap) }
        if coverSlipName != old.coverSlipName {
            model.setCoverSlip(CoverSlipShape(rawValue: coverSlipName) ?? .square)
        }
        if spotModeName != old.spotModeName { model.setSpotMode(spotMode) }
        if coverageStep != old.coverageStep { model.setCoverageStep(coverageStep) }
        if countsOrganisms != old.countsOrganisms { model.setCountsOrganisms(countsOrganisms) }
        if showsDetections != old.showsDetections { model.setShowsDetections(showsDetections) }
        if cropsToEyepiece != old.cropsToEyepiece { model.setCropsToEyepiece(cropsToEyepiece) }
        if confidence != old.confidence { model.setMinimumConfidence(Float(confidence)) }
        if detectorModelName != old.detectorModelName {
            model.setDetectorModel(DetectorModel(rawValue: detectorModelName) ?? .v3)
        }
        if detectorUnitsName != old.detectorUnitsName {
            model.setDetectorUnits(DetectorUnits(rawValue: detectorUnitsName) ?? .neuralEngine)
        }
        if cameraRateName != old.cameraRateName {
            model.setCameraRate(CameraRate(rawValue: cameraRateName) ?? .fps20)
        }
        if heatAdaptive != old.heatAdaptive { model.setHeatAdaptive(heatAdaptive) }
        if modelRateCap != old.modelRateCap { model.setModelRateCap(modelRateCap) }
        if recordsLensVideo != old.recordsLensVideo { model.setRecordsLensVideo(recordsLensVideo) }
        if mappingName != old.mappingName || mirrored != old.mirrored {
            model.setScreenMapping(mapping, mirrored: mirrored)
        }
    }
}

/// Reads the lab's stored settings, applies them when the screen opens and keeps the engine
/// in step as they change. `onReady` runs right after the first apply (the lab and the page
/// start the camera there). `transform` is for a screen with overrides; the lab has none.
struct LabSettingsSync: ViewModifier {
    var model: ScanEngine
    var transform: (LabSettings) -> LabSettings = { $0 }
    var onReady: () -> Void

    #if DEBUG
        @AppStorage("slideLab.mapping") private var mappingName = ScreenMapping.rotateRight.rawValue
        @AppStorage("slideLab.mirror") private var mirrored = false
        @AppStorage("slideLab.fieldRegion") private var fieldRegionName = FieldRegionMode.auto.rawValue
        @AppStorage("slideLab.hopAgreement") private var hopAgreement = false
        @AppStorage("slideLab.showsSees") private var showsSees = false
        @AppStorage("slideLab.guideDryRun") private var guideDryRun = false
        @AppStorage("slideLab.pauseOnMonitor") private var pausesOnMonitor = true
        @AppStorage("slideLab.trackSparse") private var tracksSparse = true
        @AppStorage("slideLab.fullCoverSlip") private var fullCoverSlip = true
        @AppStorage("slideLab.askEdges") private var asksEdges = true
        @AppStorage("slideLab.followSlipTilt") private var followsSlipTilt = true
        @AppStorage("slideLab.showLifeOnMap") private var showsLifeOnMap = true
        @AppStorage("slideLab.coverSlipShape") private var coverSlipName = CoverSlipShape.square.rawValue
        @AppStorage("slideLab.skipAlignFocus") private var skipsAlignFocus = false
        @AppStorage("slideLab.spotMode") private var spotModeName = "briefTouch"
        @AppStorage("slideLab.coverageStep") private var coverageStep = 0.8
        @AppStorage("slideLab.countOrganisms") private var countsOrganisms = true
        @AppStorage("slideLab.showDetections") private var showsDetections = false
        @AppStorage("slideLab.cropEyepiece") private var cropsToEyepiece = true
        @AppStorage("slideLab.confidence07") private var confidence = OrganismDetector.defaultConfidence
        @AppStorage("slideLab.detectorModel") private var detectorModelName = DetectorModel.v3.rawValue
        @AppStorage("slideLab.detectorUnits") private var detectorUnitsName = DetectorUnits
            .neuralEngine.rawValue
        @AppStorage("slideLab.cameraRate") private var cameraRateName = CameraRate.fps20.rawValue
        @AppStorage("slideLab.heatAdaptive") private var heatAdaptive = true
        @AppStorage("slideLab.modelRateCap") private var modelRateCap = true
        @AppStorage("slideLab.recordLensVideo") private var recordsLensVideo = false
    #endif

    private var settings: LabSettings {
        #if DEBUG
            transform(
                LabSettings(
                    mappingName: mappingName, mirrored: mirrored, fieldRegionName: fieldRegionName,
                    hopAgreement: hopAgreement, showsSees: showsSees, guideDryRun: guideDryRun,
                    pausesOnMonitor: pausesOnMonitor, tracksSparse: tracksSparse,
                    fullCoverSlip: fullCoverSlip, asksEdges: asksEdges, followsSlipTilt: followsSlipTilt,
                    showsLifeOnMap: showsLifeOnMap, coverSlipName: coverSlipName,
                    skipsAlignFocus: skipsAlignFocus, spotModeName: spotModeName,
                    coverageStep: coverageStep, countsOrganisms: countsOrganisms,
                    showsDetections: showsDetections, cropsToEyepiece: cropsToEyepiece,
                    confidence: confidence, detectorModelName: detectorModelName,
                    detectorUnitsName: detectorUnitsName, cameraRateName: cameraRateName,
                    heatAdaptive: heatAdaptive, modelRateCap: modelRateCap,
                    recordsLensVideo: recordsLensVideo))
        #else
            // No lab in Release: the chosen defaults.
            transform(LabSettings.releaseDefaults)
        #endif
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                settings.apply(to: model)
                onReady()
            }
            .onChange(of: settings) { old, new in new.applyChanges(from: old, to: model) }
    }
}
