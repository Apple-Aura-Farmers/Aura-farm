import Foundation

/// Which Supabase project the phone talks to, read from the build settings.
///
/// The values come from Config/Local.xcconfig by way of the Info.plist, and that file is
/// gitignored, so a checkout has none of them. The app has to keep working in that state:
/// a sweep is saved to the phone first and sent afterwards, so a missing project costs the
/// sending and nothing else.
struct SupabaseConfig: Equatable {
    var url: URL
    /// Safe to ship in the app. It only reaches rows that the project's row-level security
    /// policies allow the signed-in user to see.
    var anonKey: String

    /// nil when either value is blank, which is what an unconfigured checkout looks like.
    ///
    /// shortcut: hosted projects only, because the URL is built from the ref. A self-hosted
    /// project would need the whole URL in the build settings instead.
    init?(projectRef: String?, anonKey: String?) {
        guard let ref = projectRef?.trimmingCharacters(in: .whitespacesAndNewlines),
            let key = anonKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            !ref.isEmpty, !key.isEmpty,
            let url = URL(string: "https://\(ref).supabase.co")
        else { return nil }
        self.url = url
        self.anonKey = key
    }

    /// What this build was compiled with. nil where Config/Local.xcconfig is missing or blank.
    static var fromBundle: SupabaseConfig? {
        SupabaseConfig(
            projectRef: Bundle.main.object(forInfoDictionaryKey: "AURA_SUPABASE_PROJECT_REF")
                as? String,
            anonKey: Bundle.main.object(forInfoDictionaryKey: "AURA_SUPABASE_ANON_KEY") as? String
        )
    }
}
