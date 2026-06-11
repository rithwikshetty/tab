import SwiftUI
import SwiftData

struct ActivityView: View {
    var onOpen: (ActivityTarget) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(sort: \ActivityEntity.timestamp, order: .reverse) private var activities: [ActivityEntity]
    @Query private var profiles: [ProfileEntity]
    @Query private var people: [TripPersonEntity]
    @Query private var mutes: [TripMuteEntity]

    /// Cursor snapshot taken when the tab opens, so events new *this* visit stay
    /// highlighted even though opening also advances the persisted cursor (badge).
    @State private var displaySince: Date?

    private var currentUserID: UUID? { auth.currentUser?.id }

    private var mutedTripIDs: Set<UUID> {
        Set(mutes.filter(\.isMuted).map(\.tripID))
    }

    private var myTripPersonIDs: Set<UUID> {
        guard let uid = currentUserID else { return [] }
        return Set(people.filter { $0.userID == uid }.map(\.id))
    }

    private var sections: [ActivitySection] {
        guard let uid = currentUserID else { return [] }
        return ActivityPresenter.sections(
            from: activities,
            currentUserID: uid,
            lastSeenAt: displaySince,
            mutedTripIDs: mutedTripIDs,
            myTripPersonIDs: myTripPersonIDs
        )
    }

    var body: some View {
        // Hoisted so the feed presenter runs once per render, not once per access.
        let sections = self.sections

        ScrollView {
            LargeTitle(title: "Activity")

            if sections.isEmpty {
                EmptyActivityView()
            } else {
                ForEach(sections) { section in
                    Text(section.dateLabel.uppercased())
                        .font(.dateHeader)
                        .tracking(1.32)
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                Button {
                                    Haptics.light()
                                    onOpen(row.target)
                                } label: {
                                    ActivityRowView(row: row)
                                }
                                .buttonStyle(.plain)
                                if index < section.rows.count - 1 { RowDivider() }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 120)
        }
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .refreshable { await sync.pullAll() }
        .onAppear {
            // Snapshot the cursor once per visit (so newly-arrived events stay
            // highlighted), then advance the persisted cursor to clear the badge.
            // Guarded on nil so popping back from a detail — which also fires
            // onAppear — doesn't re-snapshot the just-advanced cursor and wipe
            // the "unread this visit" highlights.
            guard displaySince == nil else { return }
            displaySince = profiles.first { $0.id == currentUserID }?.activityLastSeenAt
            Task { await sync.markActivitySeen() }
        }
        .task(id: currentUserID) {
            await sync.pullAll()
        }
    }
}

private struct ActivityRowView: View {
    let row: ActivityRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill((row.isNegative ? Sage.warning : Sage.accent).opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: row.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(row.isNegative ? Sage.warning : Sage.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 15, weight: row.isUnread ? .semibold : .regular))
                    .foregroundStyle(Sage.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(row.tripName)
                    if let detail = row.detail {
                        Text("·")
                        Text(detail)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Sage.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let trailing = row.trailing {
                    Text(trailing)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Sage.text)
                        .monospacedDigit()
                }
                Text(row.timeText)
                    .font(.system(size: 11))
                    .foregroundStyle(Sage.textSecondary)
            }

            if row.isUnread {
                Circle()
                    .fill(Sage.accent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("No activity yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Updates from your trips show up here")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}
