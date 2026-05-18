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

                    Text("Trips are private to members. You can invite people once it's created.")
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
        let member = TripMemberEntity(userID: user.id, trip: trip)
        context.insert(member)

        #if DEBUG
        insertDemoMembers(into: trip, currentUserID: user.id)
        #endif

        try? context.save()

        Haptics.success()
        dismiss()

        Task { await sync.pushPending() }
    }

    #if DEBUG
    private func insertDemoMembers(into trip: TripEntity, currentUserID: UUID) {
        let existingProfiles = (try? context.fetch(FetchDescriptor<ProfileEntity>())) ?? []
        var existingProfileIDs = Set(existingProfiles.map(\.id))

        for demo in DemoTripMember.all where demo.id != currentUserID {
            if !existingProfileIDs.contains(demo.id) {
                context.insert(ProfileEntity(id: demo.id, displayName: demo.displayName))
                existingProfileIDs.insert(demo.id)
            }
            context.insert(TripMemberEntity(userID: demo.id, trip: trip))
        }
    }
    #endif
}

#if DEBUG
private struct DemoTripMember {
    let id: UUID
    let displayName: String

    static let all: [DemoTripMember] = [
        DemoTripMember(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            displayName: "Alex Demo"
        ),
        DemoTripMember(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            displayName: "Sam Demo"
        ),
    ]
}
#endif
