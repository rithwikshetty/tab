import SwiftUI

struct InviteSheet: View {
    let tripID: UUID
    let tripName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(InviteService.self) private var invites
    @Environment(SyncService.self) private var sync

    private enum Phase: Equatable {
        case loading
        case ready(InviteLink)
        case error(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Share this link with anyone you want in the trip. They'll join automatically when they tap it.")
                        .font(.system(size: 14))
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 24)

                    body(for: phase)
                        .padding(.horizontal, 22)

                    Spacer(minLength: 32)
                }
            }
            .background(Sage.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.navLink)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .principal) {
                    Text("Invite to \(tripName)")
                        .font(.navTitle)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                        .lineLimit(1)
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func body(for phase: Phase) -> some View {
        switch phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(Sage.accent)
                Text("Generating link…")
                    .font(.system(size: 14))
                    .foregroundStyle(Sage.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)

        case .ready(let link):
            ready(link: link)

        case .error(let message):
            VStack(spacing: 16) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Sage.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Button {
                    Task { await load() }
                } label: {
                    Text("Try again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Sage.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 24)
        }
    }

    @ViewBuilder
    private func ready(link: InviteLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Sage.accent)
                Text(link.url.absoluteString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = link.url.absoluteString
                    Haptics.success()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy link")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Sage.cardBorder, lineWidth: 1)
            )

            ShareLink(
                item: link.url,
                subject: Text("Join \(tripName) on tab"),
                message: Text(Self.shareMessage(tripName: tripName, url: link.url))
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Share invite link")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Sage.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { Haptics.medium() })

            Text(Self.expiryLine(for: link.expiresAt))
                .font(.system(size: 12))
                .foregroundStyle(Sage.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private func load() async {
        phase = .loading
        do {
            try await sync.ensureTripUploaded(tripID: tripID)
            let link = try await invites.createInvite(tripID: tripID)
            phase = .ready(link)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private static func expiryLine(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: .now)
        return "Link expires \(relative)"
    }

    private static func shareMessage(tripName: String, url: URL) -> String {
        """
        You're invited to join \(tripName) on tab.

        Tap the link to join the trip and split expenses together:
        \(url.absoluteString)
        """
    }
}
