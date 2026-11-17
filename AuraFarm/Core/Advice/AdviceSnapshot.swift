//
//  AdviceSnapshot.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 13/11/26.
//

import Foundation

/// A copy of what one piece of advice was based on, kept beside it.
///
/// The advice is shown again as it is while what it was based on still holds. When the soil
/// measurements differ from the copy, the advice is written again.
struct AdviceSnapshot: Codable, Equatable {
    /// The microscope test the advice is about.
    var sampleID: String
    var testRecordedAt: Date
    /// How many earlier samples of the same plot it was compared with.
    var earlierSamples: Int
    /// The soil measurements it was written with. nil when there were none to use.
    var soil: SoilInputs?
}

extension AdviceSnapshot {
    init(context: AdviceContext) {
        self.init(
            sampleID: context.result.sampleID, testRecordedAt: context.result.recordedAt,
            earlierSamples: context.history.count, soil: SoilInputs(context.result.soil))
    }
}
