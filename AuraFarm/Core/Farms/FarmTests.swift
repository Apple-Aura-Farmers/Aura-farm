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
    /// The counted tests taken on a farm, newest first.
    ///
    /// A test belongs to a farm through the farm's id, which the microscope operator's test
    /// recorded when the farm was chosen. Tests taken before farms could be chosen carry no id
    /// and belong to none. A test the detector never counted has nothing to show, so it is
    /// left out.
    ///
    /// Reads every saved sweep from disk, so call it off the main thread.
    static func load(for farmID: UUID) -> [FarmTest] {
        let estimator = PlaceholderSoilHealthEstimator()
        return SweepLibrary.sweeps()
            .filter { sweep in
                sweep.manifest?.details.farmID == farmID && sweep.manifest?.organismCounts != nil
            }
            .compactMap { sweep in
                guard let result = try? SoilResult(sweep: sweep) else { return nil }
                return FarmTest(sweep: sweep, result: result, estimate: estimator.estimate(result))
            }
    }
}
