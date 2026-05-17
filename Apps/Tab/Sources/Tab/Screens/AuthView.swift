import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthService.self) private var auth

    @State private var email: String = ""
    @State private var code: String = ""
    @State private var stage: Stage = .email
    @State private var status: Status = .idle
    @State private var appleNonce: String?
    @FocusState private var focused: Field?

    enum Stage { case email, code }
    enum Field { case email, code }
    enum Status: Equatable {
        case idle
        case sending
        case sent
        case verifying
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

            Group {
                switch stage {
                case .email: emailForm
                case .code: codeForm
                }
            }
            .animation(.easeOut(duration: 0.18), value: stage)

            statusLine

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Sage.bg.ignoresSafeArea())
        .onAppear { focused = .email }
    }

    private var emailForm: some View {
        VStack(spacing: 16) {
            appleSignInButton

            HStack(spacing: 12) {
                Rectangle().fill(Sage.rowDivider).frame(height: 1)
                Text("or")
                    .font(.system(size: 12))
                    .foregroundStyle(Sage.textSecondary)
                Rectangle().fill(Sage.rowDivider).frame(height: 1)
            }
            .padding(.vertical, 2)

            TextField("you@example.com", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .submitLabel(.send)
                .focused($focused, equals: .email)
                .onSubmit { Task { await sendCode() } }
                .font(.system(size: 17))
                .foregroundStyle(Sage.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Sage.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )

            primaryButton(
                title: "Send code",
                loading: status == .sending,
                disabled: !canSend,
                action: { Task { await sendCode() } }
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
            status = .verifying
            do {
                try await auth.signInWithApple(idToken: idToken, nonce: rawNonce)
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

    private var codeForm: some View {
        VStack(spacing: 12) {
            Text("Code sent to \(email)")
                .font(.system(size: 13))
                .foregroundStyle(Sage.textSecondary)
                .lineLimit(1)

            TextField("Code", text: $code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .focused($focused, equals: .code)
                .submitLabel(.go)
                .onSubmit { Task { await verifyCode() } }
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .tracking(6)
                .foregroundStyle(Sage.text)
                .padding(.vertical, 14)
                .background(Sage.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
                .onChange(of: code) { _, new in
                    let cleaned = String(new.filter(\.isNumber).prefix(10))
                    if cleaned != new { code = cleaned }
                }

            primaryButton(
                title: "Verify",
                loading: status == .verifying,
                disabled: !canVerify,
                action: { Task { await verifyCode() } }
            )

            Button {
                stage = .email
                code = ""
                status = .idle
                focused = .email
            } label: {
                Text("Use a different email")
                    .font(.system(size: 14))
                    .foregroundStyle(Sage.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var canVerify: Bool {
        code.count >= 6 && status != .verifying
    }

    private func primaryButton(
        title: String,
        loading: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(loading ? 0 : 1)
                if loading {
                    ProgressView().tint(.white)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                (disabled ? Sage.accent.opacity(0.4) : Sage.accent),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            switch status {
            case .idle, .sending, .verifying:
                Color.clear
            case .sent:
                Label("Check your email", systemImage: "envelope")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.accent)
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

    private var canSend: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && status != .sending
    }

    private func sendCode() async {
        guard canSend else { return }
        status = .sending
        do {
            try await auth.sendOTP(email: email.trimmingCharacters(in: .whitespaces))
            status = .sent
            stage = .code
            focused = .code
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func verifyCode() async {
        status = .verifying
        do {
            try await auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespaces),
                token: code
            )
            // AuthService will publish the .signedIn phase via authStateChanges.
        } catch {
            status = .error(error.localizedDescription)
            code = ""
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
}
