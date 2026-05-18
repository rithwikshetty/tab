import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthService.self) private var auth

    @State private var status: Status = .idle
    @State private var appleNonce: String?

    enum Status: Equatable {
        case idle
        case signingIn
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 6) {
                Text("tab")
                    .font(.system(size: 44, weight: .semibold))
                    .tracking(-1.4)
                    .foregroundStyle(Sage.text)
                Text("trip expenses, no friction")
                    .font(.system(size: 14))
                    .foregroundStyle(Sage.textSecondary)
            }

            Spacer()

            VStack(spacing: 14) {
                appleSignInButton
                Text("Sign in required")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
            }

            statusLine

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Sage.bg.ignoresSafeArea())
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let raw = SignInWithAppleHelpers.randomNonce()
            appleNonce = raw
            request.requestedScopes = [.fullName, .email]
            request.nonce = SignInWithAppleHelpers.sha256(raw)
        } onCompletion: { result in
            Task { await handleAppleResult(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let rawNonce = appleNonce
            else {
                status = .error("Apple didn't return an identity token")
                return
            }
            status = .signingIn
            do {
                try await auth.signInWithApple(
                    idToken: idToken,
                    nonce: rawNonce,
                    fullName: appleDisplayName(from: credential.fullName)
                )
                // AuthService will publish .signedIn via authStateChanges
            } catch {
                status = .error(error.localizedDescription)
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                status = .idle
            } else {
                status = .error(error.localizedDescription)
            }
        }
    }

    private func appleDisplayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        if let givenName = components.givenName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !givenName.isEmpty {
            return givenName
        }

        let formatted = components.formatted().trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            switch status {
            case .idle, .signingIn:
                Color.clear
            case .error(let message):
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.warning)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(height: 36)
        .padding(.top, 18)
        .animation(.easeOut(duration: 0.15), value: status)
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
}
