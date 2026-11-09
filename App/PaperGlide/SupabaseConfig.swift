import Foundation

/// URL and anon key baked in from `App/Config/Supabase.xcconfig`.
/// A placeholder, or a missing value, leaves the app offline. The service-role key is never read.
struct SupabaseConfig {
    var url: URL?
    var anonKey: String
    var isConfigured: Bool

    static func load(bundle: Bundle = .main) -> SupabaseConfig {
        let rawURL = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = URL(string: rawURL)
        let host = url?.host?.lowercased() ?? ""
        let placeholderHost = host.isEmpty || host.contains("your_project") || host.contains("example")
        let placeholderKey = key.isEmpty
            || key.localizedCaseInsensitiveContains("YOUR_SUPABASE")
            || key.localizedCaseInsensitiveContains("your-anon")
            || key.localizedCaseInsensitiveContains("service_role")
        let configured = url?.scheme == "https"
            && host.hasSuffix("supabase.co")
            && !placeholderHost
            && !placeholderKey
        return SupabaseConfig(url: url, anonKey: key, isConfigured: configured)
    }
}
