//
//  SampleDetails+Farm.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import Foundation

extension Farm {
    /// Where the land is, in one line: the middle of the outline as latitude and longitude.
    /// What a sample records as its location when it is taken from this farm.
    var locationDescription: String {
        guard let middle = LandGeometry.centre(of: corners) else { return "" }
        return String(format: "%.5f, %.5f", middle.latitude, middle.longitude)
    }
}

extension SampleDetails {
    /// Fills in everything a sample takes from its farm, so none of it is typed.
    ///
    /// A farm is one outline today, so the farm is also the plot: earlier samples of the same
    /// plot are the earlier samples of the same farm. If farms ever hold several plots, the plot
    /// name is the one line to change here.
    mutating func use(_ farm: Farm) {
        farmID = farm.id
        sampleID = farm.farmerName
        location = farm.locationDescription
        plotName = farm.farmerName
    }
}
