import SwiftUI
import SwiftData

struct NewTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && auth.currentUser != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    sectionLabel("Trip name")

                    TextField("Lisbon weekend", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .accessibilityIdentifier("newTrip.nameField")
                        .onSubmit { save() }
                        .font(.formRow)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Sage.rowDivider).frame(height: 1)
                        }

                    Text("Trips are private to people you add by email.")
                        .font(.system(size: 13))
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 32)
                }
            }
            .background(Sage.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.navLink)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .principal) {
                    Text("New trip")
                        .font(.navTitle)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { save() }
                        .font(.navLinkBold)
                        .foregroundStyle(canCreate ? Sage.accent : Sage.accent.opacity(0.4))
                        .disabled(!canCreate)
                        .accessibilityIdentifier("newTrip.createButton")
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { nameFocused = true }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard canCreate, let user = auth.currentUser else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        let trip = TripEntity(name: trimmed, createdByID: user.id)
        context.insert(trip)
        let person = TripPersonEntity(
            userID: user.id,
            email: user.email.map(Self.normalizedEmail) ?? "\(user.id.uuidString.lowercased())@users.tab",
            displayName: user.displayName,
            invitedByID: user.id,
            trip: trip,
            joinedAt: .now
        )
        context.insert(person)

        try? context.save()

        Haptics.success()
        dismiss()

        Task { await sync.pushPending() }
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
