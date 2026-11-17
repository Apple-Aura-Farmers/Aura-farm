//
//  SampleDetails+Farm.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import Foundation

extension Farm {
    /// Where the land is, in one line: the middle of every plot's corners as latitude and
    /// longitude. What a sample records as its location when it is taken from this farm.
    var locationDescription: String {
        guard let middle = LandGeometry.centre(of: allCorners) else { return "" }
        return String(format: "%.5f, %.5f", middle.latitude, middle.longitude)
    }
}

extension SampleDetails {
    /// Fills in everything a sample takes from its farm, so none of it is typed.
    ///
    /// shortcut: a farm now holds several plots, but a sample is still taken from the farm as
    /// a whole, so the plot name is the farmer's. Pass the plot in here once the helper picks
    /// which one a sample came from, and earlier samples of a plot stop meaning earlier
    /// samples of the farm.
    mutating func use(_ farm: Farm) {
        farmID = farm.id
        sampleID = farm.farmerName
        location = farm.locationDescription
        plotName = farm.farmerName
    }
}
