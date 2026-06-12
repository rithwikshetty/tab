import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthService.self) private var auth

    @State private var status: Status = .idle
    @State private var appleNonce: String?
    @State private var fullName = ""
    @State private var email = ""
    @State private var pendingEmail: String?
    @State private var verificationCode = ""
    @State private var captchaRequest: CaptchaRequest?

    /// A pending email-code send waiting on a Turnstile token. Tokens are
    /// single-use, so every send and resend runs the check again.
    struct CaptchaRequest: Identifiable {
        let id = UUID()
        let email: String
        let successMessage: String
    }

    enum Status: Equatable {
        case idle
        case signingIn
        case sendingCode
        case verifyingCode
        case sent(String)
        case error(String)
    }

    private var isBusy: Bool {
        switch status {
        case .signingIn, .sendingCode, .verifyingCode:
            true
        case .idle, .sent, .error:
            false
        }
    }

    private var canSendEmailCode: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    private var canVerifyCode: Bool {
        AuthService.normalizedVerificationCode(verificationCode) != nil && !isBusy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 72)

                VStack(spacing: 6) {
                    Text("tab-it")
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-1.4)
                        .foregroundStyle(Sage.text)
                    Text("keep track of shared expenses")
                        .font(.system(size: 14))
                        .foregroundStyle(Sage.textSecondary)
                }

                Spacer(minLength: 80)

                VStack(spacing: 12) {
                    appleSignInButton
                    googleSignInButton

                    HStack(spacing: 12) {
                        DividerLine()
                        Text("or")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Sage.textSecondary)
                        DividerLine()
                    }
                    .padding(.vertical, 4)

                    emailLoginSection
                }

                statusLine

                Spacer(minLength: 72)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Sage.bg.ignoresSafeArea())
        .sheet(item: $captchaRequest) { request in
            TurnstileChallengeSheet(
                siteKey: SupabaseConfig.turnstileSiteKey ?? "",
                onToken: { token in
                    captchaRequest = nil
                    Task {
                        await sendCode(
                            to: request.email,
                            successMessage: request.successMessage,
                            captchaToken: token
                        )
                    }
                },
                onCancel: {
                    captchaRequest = nil
                    status = .idle
                }
            )
        }
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
        .disabled(isBusy)
    }

    private var googleSignInButton: some View {
        Button {
            Task { await signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Text("G")
                    .font(.system(size: 17, weight: .semibold))
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Sage.text)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Sage.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    @ViewBuilder
    private var emailLoginSection: some View {
        if let pendingEmail {
            verificationSection(email: pendingEmail)
        } else {
            emailFields
            sendCodeButton

            Text("We'll email you an \(AuthService.emailVerificationCodeLength)-digit code to sign in. No password needed.")
                .font(.system(size: 12.5))
                .foregroundStyle(Sage.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var emailFields: some View {
        VStack(spacing: 10) {
            TextField("Full name", text: $fullName)
                .textContentType(.name)
                .submitLabel(.next)
                .authFieldStyle()

            TextField("Email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .authFieldStyle()
                .onSubmit {
                    guard canSendEmailCode else { return }
                    Task { await sendEmailCode() }
                }
        }
    }

    private var sendCodeButton: some View {
        accentActionButton(title: "Send Email Code", isEnabled: canSendEmailCode) {
            Task { await sendEmailCode() }
        }
        .padding(.top, 2)
    }

    private func accentActionButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Sage.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    isEnabled ? Sage.accent : Sage.surface2,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func verificationSection(email destination: String) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("Enter your code")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Sage.text)
                Text("We sent a \(AuthService.emailVerificationCodeLength)-digit code to \(destination).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Sage.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 2)

            TextField("\(AuthService.emailVerificationCodeLength)-digit code", text: $verificationCode)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .authFieldStyle()
                .onChange(of: verificationCode) { _, newValue in
                    let sanitized = String(newValue.filter(\.isNumber).prefix(AuthService.emailVerificationCodeLength))
                    if sanitized != newValue {
                        verificationCode = sanitized
                    }
                }
                .onSubmit {
                    guard canVerifyCode else { return }
                    Task { await verifyEmailCode() }
                }

            accentActionButton(title: "Verify Code", isEnabled: canVerifyCode) {
                Task { await verifyEmailCode() }
            }

            HStack(spacing: 18) {
                Button("Resend code") {
                    Task { await resendEmailCode() }
                }
                .disabled(isBusy)

                Button("Change email") {
                    resetEmailCodeFlow()
                }
                .disabled(isBusy)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Sage.accent)
            .padding(.top, 2)
        }
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
                // AuthService will publish .signedIn via authStateChanges.
            } catch {
                status = .error(error.localizedDescription)
            }
        case .failure(let error):
            if isCancellation(error) {
                status = .idle
            } else {
                status = .error(error.localizedDescription)
            }
        }
    }

    private func signInWithGoogle() async {
        status = .signingIn
        do {
            try await auth.signInWithGoogle()
        } catch {
            status = isCancellation(error) ? .idle : .error(error.localizedDescription)
        }
    }

    private func sendEmailCode() async {
        await requestCode(to: email, successMessage: "Code sent. Check your email and enter it here.")
    }

    private func resendEmailCode() async {
        guard let pendingEmail else { return }
        await requestCode(to: pendingEmail, successMessage: "New code sent.")
    }

    /// Runs the Turnstile check first when a site key is configured; the
    /// sheet's token callback performs the actual send.
    private func requestCode(to address: String, successMessage: String) async {
        if SupabaseConfig.turnstileSiteKey != nil {
            captchaRequest = CaptchaRequest(email: address, successMessage: successMessage)
        } else {
            await sendCode(to: address, successMessage: successMessage, captchaToken: nil)
        }
    }

    private func sendCode(to address: String, successMessage: String, captchaToken: String?) async {
        status = .sendingCode
        do {
            pendingEmail = try await auth.sendEmailCode(
                email: address,
                fullName: fullName,
                captchaToken: captchaToken
            )
            verificationCode = ""
            status = .sent(successMessage)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func verifyEmailCode() async {
        guard let pendingEmail else { return }
        status = .verifyingCode
        do {
            try await auth.verifyEmailCode(email: pendingEmail, code: verificationCode)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func resetEmailCodeFlow() {
        pendingEmail = nil
        verificationCode = ""
        status = .idle
    }

    private func appleDisplayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }

        let formatted = components.formatted().trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty {
            return formatted
        }

        let parts = [components.givenName, components.middleName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            return true
        }
        if let webError = error as? ASWebAuthenticationSessionError, webError.code == .canceledLogin {
            return true
        }
        return false
    }

    private func progressStatus(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Sage.accent)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Sage.textSecondary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            switch status {
            case .idle:
                Color.clear
            case .signingIn:
                ProgressView()
                    .tint(Sage.accent)
            case .sendingCode:
                progressStatus("Sending code...")
            case .verifyingCode:
                progressStatus("Verifying code...")
            case .sent(let message):
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            case .error(let message):
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.warning)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(height: 46)
        .padding(.top, 16)
        .animation(.easeOut(duration: 0.15), value: status)
    }
}

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Sage.cardBorder)
            .frame(height: 1)
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.system(size: 15))
            .foregroundStyle(Sage.text)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Sage.cardBorder, lineWidth: 1)
            )
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
}
