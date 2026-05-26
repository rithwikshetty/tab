import SwiftUI
import SwiftData

struct EditTripSheet: View {
    let tripID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool
    @State private var didLoad = false

    init(tripID: UUID) {
        self.tripID = tripID
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != trip?.name
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
                        .accessibilityIdentifier("editTrip.nameField")
                        .onSubmit { save() }
                        .font(.formRow)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Sage.rowDivider).frame(height: 1)
                        }

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
                    Text("Edit details")
                        .font(.navTitle)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.navLinkBold)
                        .foregroundStyle(canSave ? Sage.accent : Sage.accent.opacity(0.4))
                        .disabled(!canSave)
                        .accessibilityIdentifier("editTrip.saveButton")
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                if !didLoad, let trip {
                    name = trip.name
                    didLoad = true
                }
                nameFocused = true
            }
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
        guard canSave, let trip else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        trip.name = trimmed
        trip.updatedAt = .now
        trip.writeID = UUID()
        try? context.save()

        Haptics.success()
        dismiss()

        Task { await sync.pushPending() }
    }
}
