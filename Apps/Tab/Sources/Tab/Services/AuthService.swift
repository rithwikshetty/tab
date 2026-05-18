import Foundation
import Supabase

struct CurrentUser: Equatable, Sendable {
    let id: UUID
    let email: String?
    let displayName: String
}

@MainActor
@Observable
final class AuthService {
    enum Phase: Equatable {
        case loading
        case signedOut
        case signedIn(UUID)
    }

    private(set) var phase: Phase = .loading
    private(set) var currentUser: CurrentUser?

    private let client = SupabaseClientProvider.shared

    init() {
        #if DEBUG
        if Self.useMockAuth() {
            let id = Self.mockUserID
            currentUser = CurrentUser(id: id, email: "mock@tab.local", displayName: "Test User")
            phase = .signedIn(id)
            return
        }
        #endif

        Task { [weak self] in
            await self?.observeAuthState()
        }
    }

    #if DEBUG
    static let mockUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    var isUsingMockAuth: Bool {
        Self.useMockAuth()
    }

    private static func useMockAuth() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["TAB_REAL_AUTH"] == "1" || environment["TAB_MOCK_AUTH"] == "0" {
            return false
        }
        return true
    }
    #endif

    private func observeAuthState() async {
        for await (_, session) in client.auth.authStateChanges {
            if let session {
                let user = session.user
                let displayName = Self.displayName(from: user.email)
                currentUser = CurrentUser(id: user.id, email: user.email, displayName: displayName)
                phase = .signedIn(user.id)
            } else {
                currentUser = nil
                phase = .signedOut
            }
        }
    }

    func sendOTP(email: String) async throws {
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    func verifyOTP(email: String, token: String) async throws {
        _ = try await client.auth.verifyOTP(email: email, token: token, type: .email)
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    private static func displayName(from email: String?) -> String {
        guard let email else { return "You" }
        let prefix = email.split(separator: "@").first.map(String.init) ?? "You"
        return prefix.capitalized
    }
}
