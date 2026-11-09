//
//  UserRole.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import Foundation

/// Which job the person holding the phone is doing. It is chosen when the app first opens
/// and decides which half of the app they see.
///
/// The raw value is what gets saved, so renaming a case would send everyone back to the
/// role picker. Change the display text below instead.
enum UserRole: String, CaseIterable, Identifiable {
    case fieldHelper
    case microscopeOperator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fieldHelper: return "Field Helper"
        case .microscopeOperator: return "Microscope Operator"
        }
    }

    /// One line under the title on the role picker.
    var summary: String {
        switch self {
        case .fieldHelper: return "Work out on the farm."
        case .microscopeOperator: return "Prepare a slide, sweep it and count what is in it."
        }
    }

    var systemImage: String {
        switch self {
        case .fieldHelper: return "leaf.fill"
        case .microscopeOperator: return "microbe.fill"
        }
    }
}
