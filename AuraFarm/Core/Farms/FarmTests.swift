//
//  FarmTests.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import Foundation

/// A finished, counted test taken on a farm: the saved sweep, what it came to, and the
/// estimate drawn from it.
struct FarmTest: Identifiable {
    let sweep: SavedSweep
    let result: SoilResult
    let estimate: SoilHealthEstimate

    var id: URL { sweep.id }
}

enum FarmTests {
    /// The counted tests taken on one plot of a farm, newest first.
    ///
    /// A test belongs to a plot through the farm's and the plot's ids, which the microscope
    /// operator's test recorded when the plot was chosen. A test with a farm but no plot was
    /// taken before plots could be chosen, when a farm was its first plot, so it counts for
    /// that one. Tests taken before farms could be chosen carry no id and belong to none. A
    /// test the detector never counted has nothing to show, so it is left out.
    ///
    /// Reads every saved sweep from disk, so call it off the main thread.
    static func load(for plot: Plot, in farm: Farm) -> [FarmTest] {
        let isFirst = farm.plots.first?.id == plot.id
        let estimator = PlaceholderSoilHealthEstimator()
        return SweepLibrary.sweeps()
            .filter { sweep in
                guard let details = sweep.manifest?.details, details.farmID == farm.id,
                    sweep.manifest?.organismCounts != nil
                else { return false }
                return details.plotID == plot.id || (details.plotID == nil && isFirst)
            }
            .compactMap { sweep in
                guard let result = try? SoilResult(sweep: sweep) else { return nil }
                return FarmTest(sweep: sweep, result: result, estimate: estimator.estimate(result))
            }
    }
}
