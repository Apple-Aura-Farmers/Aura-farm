import XCTest

@testable import AuraFarm

final class UserRoleTests: XCTestCase {
    func testEveryRoleHasTheLabelTheRecordsUse() {
        XCTAssertEqual(UserRole.fieldHelper.recordValue, "field_helper")
        XCTAssertEqual(UserRole.microscopeOperator.recordValue, "microscope_operator")
    }

    func testTheSavedValueIsNotChangedByAccident() {
        // Changing a raw value sends everyone who has chosen a role back to the picker.
        XCTAssertEqual(UserRole.allCases.map(\.rawValue), ["fieldHelper", "microscopeOperator"])
    }
}
