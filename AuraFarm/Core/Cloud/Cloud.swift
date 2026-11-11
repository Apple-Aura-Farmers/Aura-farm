import Foundation
import Supabase

/// The app's one connection to Supabase.
///
/// One client for the whole app, because it holds the signed-in session and a second one
/// would not see the first one's sign-in.
enum Cloud {
    /// nil until Config/Local.xcconfig names a project. Callers treat that as "no backend
    /// today" rather than as a failure.
    static let client: SupabaseClient? = {
        guard let config = SupabaseConfig.fromBundle else { return nil }
        return SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }()

    /// Whether the project answers with the key this build carries.
    ///
    /// Asks for the REST root, which every project serves and which names no table, so a
    /// wrong project or a wrong key is told apart from a wrong table name.
    static func isReachable() async -> Bool {
        guard let config = SupabaseConfig.fromBundle else { return false }
        var request = URLRequest(url: config.url.appending(path: "rest/v1/"))
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }
}
