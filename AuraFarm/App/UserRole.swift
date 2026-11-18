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
        case .fieldHelper:
            return "collect farm data, receive scientific test results and generate actionable recommendations through AI analysis."
        case .microscopeOperator:
            return "observe soil biodiversity through your microscope, with AI-powered identification and analysis."
        }
    }

    /// The label `profiles.role` holds, which is snake_case where this enum is camel. A
    /// label the `user_role` enum does not have is refused by Postgres rather than stored.
    var recordValue: String {
        switch self {
        case .fieldHelper: return "field_helper"
        case .microscopeOperator: return "microscope_operator"
        }
    }

    /// The name of the drawing on the role picker, which has a `_Light` twin for light mode.
    var illustration: String {
        switch self {
        case .fieldHelper: return "Field_Helper"
        case .microscopeOperator: return "Scientist"
        }
    }
}
