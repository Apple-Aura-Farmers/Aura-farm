//
//  AdviceUpdateNote.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 13/11/26.
//

import Foundation

/// The one line that says why advice was written again: "Updated with the new pH reading."
///
/// PROVISIONAL: wording written for the prototype.
enum AdviceUpdateNote {
    /// `old` is what the earlier advice was written with, and `new` what the new advice was.
    static func text(from old: SoilInputs?, to new: SoilInputs?) -> String {
        guard let new else { return String(localized: "Updated after the soil measurements were removed.") }
        guard let old else { return String(localized: "Updated with the new soil measurements.") }

        let before = values(old)
        let after = values(new)
        let changed = order.filter { before[$0] != after[$0] }
        if changed.isEmpty, old.fertilizerType != new.fertilizerType {
            return String(localized: "Updated with the new fertilizer type.")
        }
        if changed.isEmpty, old.phFieldWater != new.phFieldWater {
            return String(localized: "Updated with how the pH was measured.")
        }
        guard changed.count == 1, let changedName = changed.first else {
            return String(localized: "Updated with the new soil measurements.")
        }
        // The reading's name in the phone's language. The English names stay the keys above.
        let name = changedName.translated
        return after[changedName] == nil
            ? String(localized: "Updated after the \(name) reading was removed.")
            : String(localized: "Updated with the new \(name) reading.")
    }

    private static let order = ["nitrogen", "phosphorus", "potassium", "pH", "organic carbon"]

    private static func values(_ inputs: SoilInputs) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: inputs.readings.map { ($0.name, $0.value) })
    }
}
