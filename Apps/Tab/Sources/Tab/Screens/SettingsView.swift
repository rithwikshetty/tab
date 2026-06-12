import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PushService.self) private var push

    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            LargeTitle(title: "Settings")

            if let user = auth.currentUser {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Sage.text)
                        if let email = user.presentableEmail {
                            Text(email)
                                .font(.system(size: 13))
                                .foregroundStyle(Sage.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }

            SectionHeaderText(title: "Notifications")
            Card {
                NotificationStatusRow(status: push.authorizationStatus)
                    .padding(16)
            }

            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Sage.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .padding(.top, 24)
            .disabled(isDeletingAccount)

            Button {
                deleteError = nil
                showDeleteConfirmation = true
            } label: {
                Group {
                    if isDeletingAccount {
                        ProgressView()
                            .tint(Sage.warning)
                    } else {
                        Text("Delete account")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Sage.warning)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .disabled(isDeletingAccount)

            if let deleteError {
                Text(deleteError)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 120)
        }
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .task { await push.refreshAuthorizationStatus() }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account. Trips only you joined are erased, including their expenses. In shared trips, expenses stay visible to other members, but your email and profile are removed. This cannot be undone.")
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await auth.deleteAccount()
        } catch {
            deleteError = "Couldn't delete your account. Check your connection and try again."
        }
    }
}

private struct NotificationStatusRow: View {
    let status: UNAuthorizationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Push notifications")
                    .font(.system(size: 15))
                    .foregroundStyle(Sage.text)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Sage.textSecondary)
            }
            Spacer()
            if status == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Sage.accent)
            }
        }
    }

    private var icon: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "bell.fill"
        case .denied: "bell.slash.fill"
        default: "bell"
        }
    }

    private var tint: Color {
        switch status {
        case .authorized, .provisional, .ephemeral: Sage.accent
        case .denied: Sage.warning
        default: Sage.textSecondary
        }
    }

    private var label: String {
        switch status {
        case .authorized: "On"
        case .provisional: "Quiet delivery"
        case .ephemeral: "Limited"
        case .denied: "Off. Enable it in iOS Settings"
        case .notDetermined: "Not set up yet"
        @unknown default: "Unknown"
        }
    }
}
