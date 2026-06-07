import SwiftUI
import SwiftData
import TabCore

/// Step 1 of the global "Add expense" flow (people-first). Pick who's involved and,
/// optionally, a trip to file it under. "No group" resolves a hidden non-group
/// container from the chosen people; a trip routes straight to that trip. Either way
/// it hands a destination container id to `onResolved`, which swaps this screen for
/// the standard expense form.
struct NonGroupExpenseFlowView: View {
    var onResolved: (UUID) -> Void = { _ in }

    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(
        filter: #Predicate<TripEntity> { $0.deletedAt == nil && $0.kind == "trip" },
        sort: \TripEntity.lastActivityAt, order: .reverse
    )
    private var trips: [TripEntity]

    @State private var selected: [PickedPerson] = []
    @State private var selectedTripID: UUID?
    @State private var query: String = ""
    @State private var suggestions: [TripPersonSuggestionDTO] = []
    @State private var isResolving = false
    @State private var errorText: String?

    private struct PickedPerson: Identifiable, Hashable {
        let email: String        // normalized
        let displayName: String
        var id: String { email }
    }

    private var selectedTrip: TripEntity? {
        guard let id = selectedTripID else { return nil }
        return trips.first { $0.id == id }
    }

    private var canProceed: Bool {
        if selectedTrip != nil { return true }
        return !selected.isEmpty && !isResolving
    }

    private var filteredSuggestions: [TripPersonSuggestionDTO] {
        let chosen = Set(selected.map(\.email))
        return suggestions.filter {
            let email = normalized($0.email)
            return !chosen.contains(email) && email != currentUserEmail
        }
    }

    private var hasSuggestionContent: Bool {
        !filteredSuggestions.isEmpty || canInviteEmail(query)
    }

    private var currentUserEmail: String? {
        auth.currentUser?.email.map(normalized)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                groupCard

                if selectedTrip == nil {
                    searchField
                    if !selected.isEmpty {
                        SectionHeaderText(title: "Splitting with")
                        Card { selectedRows }
                    }
                    if hasSuggestionContent {
                        SectionHeaderText(title: query.isEmpty ? "People you split with" : "Results")
                        Card { suggestionRows }
                    } else if selected.isEmpty {
                        Text("Search for someone you've split with, or type an email to invite them.")
                            .font(.system(size: 13))
                            .foregroundStyle(Sage.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 40)
                            .padding(.top, 28)
                    }
                } else {
                    tripNote
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Sage.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                }

                Spacer(minLength: 24)
            }
        }
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .navigationTitle("New expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isResolving {
                    ProgressView().controlSize(.small).tint(Sage.accent)
                } else {
                    Button("Next") { proceed() }
                        .font(.navLinkBold)
                        .foregroundStyle(canProceed ? Sage.accent : Sage.accent.opacity(0.4))
                        .disabled(!canProceed)
                }
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .task(id: query) { await loadSuggestions() }
    }

    // MARK: - Group selector

    private var groupCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: selectedTrip == nil ? "person.2.fill" : "suitcase.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Sage.accent)
                    .frame(width: 30, height: 30)
                    .background(Sage.iconBg, in: RoundedRectangle(cornerRadius: 9))
                Text("Group")
                    .font(.formRowLabel)
                    .foregroundStyle(Sage.text)
                Spacer()
                Menu {
                    Button { selectedTripID = nil } label: {
                        Label("No group", systemImage: selectedTripID == nil ? "checkmark" : "")
                    }
                    if !trips.isEmpty {
                        Divider()
                        ForEach(trips) { trip in
                            Button { selectedTripID = trip.id } label: {
                                Label(trip.name, systemImage: selectedTripID == trip.id ? "checkmark" : "")
                            }
                        }
                    }
                } label: {
                    DropdownPill(title: selectedTrip?.name ?? "No group")
                        .frame(maxWidth: 190, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newExpense.groupMenu")
            }
            .padding(14)
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
            TextField("Search or enter email", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .font(.system(size: 15))
                .submitLabel(.done)
                .onSubmit { addEmailIfValid(query) }
                .accessibilityIdentifier("newExpense.searchField")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var selectedRows: some View {
        ForEach(Array(selected.enumerated()), id: \.element.id) { index, person in
            HStack(spacing: 12) {
                Avatar(initial: AvatarInitial.from(person.displayName),
                       tone: AvatarTone.deterministic(for: deterministicID(person.email)), size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(Sage.text)
                        .lineLimit(1).truncationMode(.tail)
                    Text(person.email).font(.system(size: 12)).foregroundStyle(Sage.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.light()
                    selected.removeAll { $0.email == person.email }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Sage.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Sage.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            if index < selected.count - 1 { RowDivider() }
        }
    }

    @ViewBuilder
    private var suggestionRows: some View {
        let rows = filteredSuggestions
        if rows.isEmpty && canInviteEmail(query) {
            addEmailRow(query)
        } else {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, s in
                Button {
                    Haptics.light()
                    selected.append(PickedPerson(email: normalized(s.email), displayName: s.displayName))
                    query = ""
                } label: {
                    HStack(spacing: 12) {
                        Avatar(initial: AvatarInitial.from(s.displayName),
                               tone: AvatarTone.deterministic(for: deterministicID(s.email)), size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(Sage.text)
                                .lineLimit(1).truncationMode(.tail)
                            Text(s.email).font(.system(size: 12)).foregroundStyle(Sage.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18)).foregroundStyle(Sage.accent)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < rows.count - 1 { RowDivider() }
            }
            if canInviteEmail(query) {
                if !rows.isEmpty { RowDivider() }
                addEmailRow(query)
            }
        }
    }

    private func addEmailRow(_ email: String) -> some View {
        Button {
            Haptics.light()
            addEmailIfValid(email)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 14)).foregroundStyle(Sage.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Sage.surface2, in: Circle())
                Text("Invite \(normalized(email))")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Sage.accentStrong)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "plus.circle").font(.system(size: 18)).foregroundStyle(Sage.accent)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newExpense.inviteButton")
    }

    private var tripNote: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill").foregroundStyle(Sage.accent)
                Text("Everyone in \(selectedTrip?.name ?? "the trip") will be included.")
                    .font(.system(size: 14)).foregroundStyle(Sage.text)
                Spacer()
            }
            .padding(14)
        }
        .padding(.top, 14)
    }

    // MARK: - Actions

    private func proceed() {
        errorText = nil
        if let trip = selectedTrip {
            onResolved(trip.id)
            return
        }
        guard !selected.isEmpty else { return }
        isResolving = true
        Task {
            do {
                let participants = selected.map { (email: $0.email, displayName: $0.displayName) }
                let containerID = try await sync.resolveNonGroupContainer(participants: participants)
                await MainActor.run {
                    isResolving = false
                    onResolved(containerID)
                }
            } catch {
                await MainActor.run {
                    isResolving = false
                    errorText = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't start this expense. Check your connection and try again."
                }
            }
        }
    }

    private func loadSuggestions() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        do {
            suggestions = try await sync.suggestTripPeople(query: q.isEmpty ? nil : q)
        } catch {
            suggestions = []
        }
    }

    private func addEmailIfValid(_ raw: String) {
        let email = normalized(raw)
        guard canInviteEmail(email), !selected.contains(where: { $0.email == email }) else { return }
        selected.append(PickedPerson(email: email, displayName: localPart(email)))
        query = ""
    }

    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func localPart(_ email: String) -> String {
        String(email.split(separator: "@").first ?? "").capitalized
    }

    private func isValidEmail(_ s: String) -> Bool {
        let e = normalized(s)
        guard e.contains("@"), let at = e.firstIndex(of: "@") else { return false }
        let domain = e[e.index(after: at)...]
        return !e[..<at].isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }

    private func canInviteEmail(_ s: String) -> Bool {
        let email = normalized(s)
        return isValidEmail(email) && email != currentUserEmail
    }

    /// Stable per-email UUID purely for picking a consistent avatar tone in this picker.
    private func deterministicID(_ email: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(email)
        let h = UInt64(bitPattern: Int64(hasher.finalize()))
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8((h >> (UInt64(i) * 8)) & 0xFF) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
