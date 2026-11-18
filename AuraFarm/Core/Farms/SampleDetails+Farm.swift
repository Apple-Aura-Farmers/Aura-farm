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

extension SampleDetails {
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
