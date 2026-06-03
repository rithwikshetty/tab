import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @State private var tab: RootTab = .trips
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ZStack {
                    TripListView { tripID in
                        path.append(Route.trip(tripID))
                    }
                    .opacity(tab == .trips ? 1 : 0)
                    .allowsHitTesting(tab == .trips)

                    SettingsPlaceholderView()
                        .opacity(tab == .settings ? 1 : 0)
                        .allowsHitTesting(tab == .settings)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabBar(selection: $tab)
            }
            .background(Sage.bg.ignoresSafeArea())
            .navigationTitle(tab == .trips ? "Trips" : "Settings")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .trip(let tripID):
                    TripDetailView(
                        tripID: tripID,
                        onAddExpense: { path.append(Route.newExpense(tripID)) },
                        onOpenExpense: { expenseID in path.append(Route.expense(expenseID)) },
                        onSettleUp: { path.append(Route.settleUp(tripID: tripID)) },
                        onOpenSettlement: { settlementID in path.append(Route.settlement(settlementID)) }
                    )
                case .newExpense(let tripID):
                    ExpenseEntryView(tripID: tripID)
                case .editExpense(let tripID, let expenseID):
                    ExpenseEntryView(tripID: tripID, editingExpenseID: expenseID)
                case .expense(let expenseID):
                    ExpenseDetailView(
                        expenseID: expenseID,
                        onEditExpense: { tripID, expenseID in
                            path.append(Route.editExpense(tripID: tripID, expenseID: expenseID))
                        }
                    )
                case .settleUp(let tripID):
                    SettleUpFormView(tripID: tripID)
                case .editSettlement(let tripID, let settlementID):
                    SettleUpFormView(tripID: tripID, editingSettlementID: settlementID)
                case .settlement(let settlementID):
                    SettlementDetailView(
                        settlementID: settlementID,
                        onEditSettlement: { tripID, settlementID in
                            path.append(Route.editSettlement(tripID: tripID, settlementID: settlementID))
                        }
                    )
                }
            }
        }
        .tint(Sage.accent)
        .task(id: auth.currentUser) {
            removeLegacyMockSeedIfNeeded()
            bootstrapProfile()
            bootstrapDefaultCategories()
            await sync.pushPending()
            await sync.claimTripPeopleForCurrentEmail()
            await sync.pullAll()
        }
    }

    private func removeLegacyMockSeedIfNeeded() {
        let seedTripID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == seedTripID })
        do {
            for trip in try context.fetch(descriptor) {
                context.delete(trip)
            }
            try context.save()
        } catch { }
    }

    private func bootstrapProfile() {
        guard let user = auth.currentUser else { return }
        let userID = user.id
        let descriptor = FetchDescriptor<ProfileEntity>(predicate: #Predicate { $0.id == userID })
        do {
            let existing = try context.fetch(descriptor)
            if let profile = existing.first {
                if profile.displayName != user.displayName {
                    profile.displayName = user.displayName
                    profile.updatedAt = .now
                    profile.writeID = UUID()
                    try context.save()
                }
            } else {
                context.insert(ProfileEntity(id: userID, displayName: user.displayName))
                try context.save()
            }
        } catch { }
    }

    private func bootstrapDefaultCategories() {
        let descriptor = FetchDescriptor<CategoryEntity>(predicate: #Predicate<CategoryEntity> { $0.isDefault })
        do {
            let existing = try context.fetch(descriptor)
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            for def in DefaultCategories.all {
                if let entity = byID[def.id] {
                    if entity.icon != def.icon { entity.icon = def.icon }
                    if entity.name != def.name { entity.name = def.name }
                } else {
                    context.insert(CategoryEntity(
                        id: def.id, tripID: nil, name: def.name, icon: def.icon, isDefault: true
                    ))
                }
            }
            try context.save()
        } catch { }
    }
}

enum Route: Hashable {
    case trip(UUID)
    case newExpense(UUID)
    case editExpense(tripID: UUID, expenseID: UUID)
    case expense(UUID)
    case settleUp(tripID: UUID)
    case editSettlement(tripID: UUID, settlementID: UUID)
    case settlement(UUID)
}

struct SettingsPlaceholderView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            if let user = auth.currentUser {
                Text(user.displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(Sage.textSecondary)

                if let presentableEmail = user.presentableEmail {
                    Text(presentableEmail)
                        .font(.system(size: 13))
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.top, 2)
                }
            }
            Spacer()

            Button("Sign out") {
                Task { await auth.signOut() }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Sage.warning)
            .padding(.bottom, 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
