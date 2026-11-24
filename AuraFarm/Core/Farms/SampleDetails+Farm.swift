//
//  SampleDetails+Farm.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import Foundation

extension Plot {
    /// Where the land is, in one line: the middle of the plot's corners as latitude and
    /// longitude. What a sample records as its location when it is taken from this plot.
    var locationDescription: String {
        guard let middle = LandGeometry.centre(of: corners) else { return "" }
        return String(format: "%.5f, %.5f", middle.latitude, middle.longitude)
    }
}

extension GeoPoint {
    /// Reads back a place written by `Plot.locationDescription`.
    ///
    /// A sample keeps its plot's middle as that one line of text, and the records want a
    /// point, so the line has to be read as numbers again. Only what that property writes is
    /// accepted: two decimal numbers, latitude first. nil for anything else, including the
    /// empty line a plot with no corners leaves.
    init?(locationDescription line: String) {
        let parts = line.split(separator: ",")
        guard parts.count == 2,
            let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
            let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }
}

extension SampleDetails {
    /// "No farm": what a farm filled in is taken out again, its name included.
    mutating func useNoFarm() {
        // Already no farm: the name is the person's own, so leave it.
        guard farmID != nil || plotID != nil || location != nil else { return }
        farmID = nil
        plotID = nil
        plotName = nil
        location = nil
        sampleID = ""
    }

    /// Fills in everything a sample takes from its plot, so none of it is typed.
    ///
    /// A farm with several plots names the plot after the farmer, so earlier samples of one
    /// plot are not taken for earlier samples of another. A farm with one keeps the farmer's
    /// name alone, as it was before plots could be chosen.
    mutating func use(_ plot: Plot?, of farm: Farm) {
        farmID = farm.id
        plotID = plot?.id
        sampleID = farm.farmerName
        location = plot?.locationDescription ?? ""
        plotName =
            if let plot, farm.plots.count > 1 {
                "\(farm.farmerName), \(farm.title(of: plot))"
            } else {
                farm.farmerName
            }
    }
}
