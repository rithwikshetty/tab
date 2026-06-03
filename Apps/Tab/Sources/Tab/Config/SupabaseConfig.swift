import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://gaseuxsieddlksxtdliq.supabase.co")!
    static let publishableKey = "sb_publishable_fTMuDzDWfOw6M7yg9PNEBA_YTsbANcQ"

    static let authCallbackScheme = "com.rithwikshetty.tab"
    static let authCallbackURL = URL(string: "\(authCallbackScheme)://auth-callback")!
}
