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
        if environment["TAB_REAL_AUTH"] == "1" {
            return false
        }
        return environment["TAB_MOCK_AUTH"] == "1"
    }
    #endif

    private func observeAuthState() async {
        for await (_, session) in client.auth.authStateChanges {
            if let session {
                let user = session.user
                let displayName = Self.displayName(from: user)
                currentUser = CurrentUser(id: user.id, email: user.email, displayName: displayName)
                phase = .signedIn(user.id)
            } else {
                currentUser = nil
                phase = .signedOut
            }
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )

        if let displayName = Self.normalizedDisplayName(fullName) {
            _ = try? await client.auth.update(
                user: UserAttributes(data: [
                    "display_name": .string(displayName),
                    "full_name": .string(displayName),
                ])
            )
            currentUser = CurrentUser(id: session.user.id, email: session.user.email, displayName: displayName)
        } else {
            let displayName = Self.displayName(from: session.user)
            currentUser = CurrentUser(id: session.user.id, email: session.user.email, displayName: displayName)
        }
        phase = .signedIn(session.user.id)
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    private static func displayName(from user: User) -> String {
        if let displayName = normalizedDisplayName(user.userMetadata["display_name"]?.stringValue) {
            return displayName
        }
        if let givenName = normalizedDisplayName(user.userMetadata["given_name"]?.stringValue) {
            return givenName
        }
        if let fullName = normalizedDisplayName(user.userMetadata["full_name"]?.stringValue) {
            return fullName
        }
        if let name = normalizedDisplayName(user.userMetadata["name"]?.stringValue) {
            return name
        }
        return displayName(from: user.email)
    }

    private static func displayName(from email: String?) -> String {
        guard let email else { return "You" }
        let prefix = email.split(separator: "@").first.map(String.init) ?? "You"
        return prefix.capitalized
    }

    private static func normalizedDisplayName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(60))
    }
}
