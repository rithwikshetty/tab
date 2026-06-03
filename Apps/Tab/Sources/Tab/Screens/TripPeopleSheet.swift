import SwiftUI
import SwiftData

struct TripPeopleSheet: View {
    let tripID: UUID
    let tripName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]

    @State private var emailText = ""
    @State private var suggestions: [TripPersonSuggestionDTO] = []
    @State private var isAdding = false
    @State private var errorMessage: String?

    @FocusState private var emailFocused: Bool

    init(tripID: UUID, tripName: String) {
        self.tripID = tripID
        self.tripName = tripName
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var normalizedEmail: String {
        emailText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canAdd: Bool {
        normalizedEmail.contains("@") && !existingEmails.contains(normalizedEmail) && !isAdding
    }

    private var existingEmails: Set<String> {
        Set((trip?.people ?? []).map(\.email))
    }

    private var filteredSuggestions: [TripPersonSuggestionDTO] {
        suggestions.filter { !existingEmails.contains($0.email) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("People")
                    peopleList

                    sectionLabel("Add by email")
                    addCard

                    if !filteredSuggestions.isEmpty {
                        sectionLabel("Suggestions")
                        suggestionList
                    }

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
                    Text("People")
                        .font(.navTitle)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await refreshSuggestions() }
            .onChange(of: emailText) { _, _ in
                Task { await refreshSuggestions() }
            }
        }
    }

    private var peopleList: some View {
        VStack(spacing: 0) {
            ForEach(Array((trip?.people.sortedForDisplay(currentPersonID: currentPersonID) ?? []).enumerated()), id: \.element.id) { index, person in
                personRow(person)
                if index < (trip?.people.count ?? 0) - 1 { RowDivider() }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Sage.accent)
                TextField("name@example.com", text: $emailText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .font(.formRow)
                    .foregroundStyle(Sage.text)
                    .submitLabel(.done)
                    .onSubmit { addEmail() }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Sage.warning)
            }

            Button {
                addEmail()
            } label: {
                HStack(spacing: 8) {
                    if isAdding {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Add person")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(canAdd ? Sage.accent : Sage.accent.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .padding(14)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredSuggestions.enumerated()), id: \.element.email) { index, suggestion in
                Button {
                    emailText = suggestion.email
                    addEmail()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(initial: AvatarInitial.from(suggestion.displayName), tone: AvatarTone.deterministic(for: suggestion.userID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!), size: 30, borderWidth: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.displayName)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(Sage.text)
                            Text(suggestion.email)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Sage.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Sage.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)

                if index < filteredSuggestions.count - 1 { RowDivider() }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var currentPersonID: UUID? {
        guard let userID = auth.currentUser?.id else { return nil }
        return trip?.people.first(where: { $0.userID == userID })?.id
    }

    private func personRow(_ person: TripPersonEntity) -> some View {
        let isYou = person.id == currentPersonID
        let emailText = currentUserEmailText(isYou: isYou, fallback: person.email)
        return HStack(spacing: 12) {
            Avatar(initial: AvatarInitial.from(isYou ? (auth.currentUser?.displayName ?? person.displayName) : person.displayName), tone: AvatarTone.deterministic(for: person.id), size: 30, borderWidth: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "You" : person.displayName)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Sage.text)
                Text(emailText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Sage.textSecondary)
            }
            Spacer()
            Text(person.joinedAt == nil ? "Pending" : "Joined")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(person.joinedAt == nil ? Sage.warning : Sage.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func currentUserEmailText(isYou: Bool, fallback: String) -> String {
        guard isYou, let user = auth.currentUser else { return fallback }
        return user.presentableEmail ?? fallback
    }

    private func addEmail() {
        guard canAdd else { return }
        let email = normalizedEmail
        isAdding = true
        errorMessage = nil

        Task {
            do {
                try await sync.addTripPerson(tripID: tripID, email: email)
                await sync.pullAll()
                await MainActor.run {
                    emailText = ""
                    isAdding = false
                    emailFocused = false
                    Haptics.success()
                }
                await refreshSuggestions()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAdding = false
                    Haptics.error()
                }
            }
        }
    }

    private func refreshSuggestions() async {
        do {
            let rows = try await sync.suggestTripPeople(query: normalizedEmail.isEmpty ? nil : normalizedEmail)
            await MainActor.run {
                suggestions = rows
            }
        } catch { }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
