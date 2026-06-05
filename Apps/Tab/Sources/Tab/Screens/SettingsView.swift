import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PushService.self) private var push

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

            Spacer(minLength: 120)
        }
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .task { await push.refreshAuthorizationStatus() }
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
        case .denied: "Off — enable in iOS Settings"
        case .notDetermined: "Not set up yet"
        @unknown default: "Unknown"
        }
    }
}
