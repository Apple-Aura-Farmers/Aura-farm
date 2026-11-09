import SwiftUI

/// Who is using the phone. The program manager and the field helpers share one phone and one
/// set of farm records, and see different screens.
///
/// A placeholder for real sign-in: anyone can switch with the toggle at the top of the screen.
enum AppRole: String, CaseIterable, Identifiable {
    case fieldHelper
    case programManager

    /// Where the chosen role is remembered between launches.
    static let storageKey = "appRole"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fieldHelper: return "Field helper"
        case .programManager: return "Program manager"
        }
    }

    var systemImage: String {
        switch self {
        case .fieldHelper: return "figure.walk"
        case .programManager: return "person.text.rectangle"
        }
    }

    /// Whether this role adds and changes farms, fields, NPK results and seasons. Field helpers
    /// see them, and the plan, to explain a result to the farmer, but do not change them.
    var canEditRecords: Bool {
        self == .programManager
    }
}

private struct CanEditRecordsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the person on the phone may change farm records. Set by `RoleRootView`.
    var canEditRecords: Bool {
        get { self[CanEditRecordsKey.self] }
        set { self[CanEditRecordsKey.self] = newValue }
    }
}
