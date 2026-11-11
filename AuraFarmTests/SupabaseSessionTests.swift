import XCTest

@testable import AuraFarm

@MainActor
final class SupabaseSessionTests: XCTestCase {
    func testABuildWithNoProjectSaysSoInsteadOfWaiting() {
        // A checkout with no Config/Local.xcconfig. The account screen has to say something
        // rather than spin on a session that will never arrive.
        XCTAssertEqual(SupabaseSession(client: nil).state, .unavailable)
    }

    func testNoProjectMeansEveryAccountRequestFailsRatherThanDoingNothing() async {
        let session = SupabaseSession(client: nil)

        await assertUnavailable { try await session.signIn(email: "a@b.c", password: "secret") }
        await assertUnavailable { try await session.signOut() }
        await assertUnavailable {
            _ = try await session.signUp(fullName: "A", email: "a@b.c", password: "secret")
        }
    }

    func testNoSessionIsSignedOutRatherThanStillLoading() {
        // What the auth change stream reports once it has looked and found nothing kept.
        XCTAssertEqual(SupabaseSession.state(for: nil), .signedOut)
    }

    private func assertUnavailable(
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("expected a failure", file: file, line: line)
        } catch {
            XCTAssertTrue(error is SupabaseSession.Failure, "got \(error)", file: file, line: line)
        }
    }
}
