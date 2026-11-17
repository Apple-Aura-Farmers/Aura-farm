import XCTest

@testable import AuraFarm

/// Taking in what the records hold, next to what this phone already had.
final class FarmStoreMergeTests: XCTestCase {
    private let square = [
        GeoPoint(latitude: -8.4095, longitude: 115.1889),
        GeoPoint(latitude: -8.4095, longitude: 115.1900),
        GeoPoint(latitude: -8.4105, longitude: 115.1900),
    ]

    func testTheRecordsCopyWinsForAFarmBothSidesHave() {
        let mine = farm(name: "Old name")
        let store = FarmStore(fileURL: nil, farms: [mine])

        var theirs = mine
        theirs.name = "Subak Jatiluwih"
        store.merge([theirs])

        XCTAssertEqual(store.farms.count, 1)
        XCTAssertEqual(store.farms.first?.name, "Subak Jatiluwih")
    }

    func testAFarmOnlyThisPhoneHasIsLeftAlone() {
        // It is one nobody has published yet, not one somebody deleted.
        let unpublished = farm(name: "Not sent yet")
        let store = FarmStore(fileURL: nil, farms: [unpublished])

        store.merge([farm(name: "From the records")])

        XCTAssertEqual(store.farms.count, 2)
        XCTAssertTrue(store.farms.contains { $0.id == unpublished.id })
    }

    func testAFarmOnlyTheRecordsHaveIsTakenIn() {
        let store = FarmStore(fileURL: nil)

        store.merge([farm(name: "Somebody else's")])

        XCTAssertEqual(store.farms.map(\.name), ["Somebody else's"])
    }

    func testMergingNothingChangesNothing() {
        let store = FarmStore(fileURL: nil, farms: [farm(name: "Mine")])

        store.merge([])

        XCTAssertEqual(store.farms.map(\.name), ["Mine"])
    }

    func testTheOldestFarmComesFirst() {
        let store = FarmStore(fileURL: nil)
        let older = farm(name: "Older", createdAt: Date(timeIntervalSince1970: 1))
        let newer = farm(name: "Newer", createdAt: Date(timeIntervalSince1970: 2))

        store.merge([newer, older])

        XCTAssertEqual(store.farms.map(\.name), ["Older", "Newer"])
    }

    private func farm(name: String, createdAt: Date = .now) -> Farm {
        Farm(
            name: name, farmerName: "Pak Wayan", plots: [Plot(corners: square)],
            createdAt: createdAt)
    }
}
