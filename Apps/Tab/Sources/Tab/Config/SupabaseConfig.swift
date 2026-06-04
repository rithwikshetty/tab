import Foundation

enum SupabaseConfig {
    private static let fallbackURLString = "https://example.supabase.co"
    private static let fallbackPublishableKey = "replace-with-supabase-publishable-key"
    private static let fallbackAuthCallbackScheme = "com.example.tab"

    static let url = URL(string: infoString("TABSupabaseURL") ?? fallbackURLString)!
    static let publishableKey = infoString("TABSupabasePublishableKey") ?? fallbackPublishableKey

    static let authCallbackScheme = infoString("TABAuthCallbackScheme") ?? fallbackAuthCallbackScheme
    static let authCallbackURL = URL(string: "\(authCallbackScheme)://auth-callback")!

    static var isConfigured: Bool {
        url.absoluteString != fallbackURLString && publishableKey != fallbackPublishableKey
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}
