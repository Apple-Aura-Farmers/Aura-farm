import XCTest

@testable import AuraFarm

final class SupabaseConfigTests: XCTestCase {
    func testABlankSettingIsNoProjectRatherThanABadURL() {
        // What a checkout with no Config/Local.xcconfig compiles to.
        XCTAssertNil(SupabaseConfig(projectRef: "", anonKey: "key"))
        XCTAssertNil(SupabaseConfig(projectRef: "   ", anonKey: "key"))
        XCTAssertNil(SupabaseConfig(projectRef: "ref", anonKey: ""))
        XCTAssertNil(SupabaseConfig(projectRef: nil, anonKey: nil))
    }

    func testTheProjectRefBecomesTheProjectURL() {
        let config = SupabaseConfig(projectRef: "abcdefghijklmnop", anonKey: "key")
        XCTAssertEqual(config?.url.absoluteString, "https://abcdefghijklmnop.supabase.co")
    }

    func testAnXcconfigLineKeepsNoTrailingSpace() {
        // An xcconfig value carries whatever is after the = sign, trailing blanks included.
        let config = SupabaseConfig(projectRef: " abcdef \n", anonKey: " key ")
        XCTAssertEqual(config?.url.absoluteString, "https://abcdef.supabase.co")
        XCTAssertEqual(config?.anonKey, "key")
    }
}
