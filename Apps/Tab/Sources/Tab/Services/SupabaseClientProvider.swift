import Foundation
import Supabase

enum SupabaseClientProvider {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey,
        options: SupabaseClientOptions(
            auth: .init(
                redirectToURL: SupabaseConfig.authCallbackURL,
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
