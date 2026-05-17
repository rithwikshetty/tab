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

                RoamTabBar(selection: $tab)
            }
            .background(Sage.bg.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .trip(let tripID):
                    TripDetailView(tripID: tripID) {
                        path.append(Route.newExpense(tripID))
                    }
                case .newExpense(let tripID):
                    ExpenseEntryView(tripID: tripID) { path.removeLast() }
                }
            }
        }
        .tint(Sage.accent)
        .task(id: auth.currentUser?.id) {
            bootstrapProfile()
            bootstrapDefaultCategories()
            #if DEBUG
            if ProcessInfo.processInfo.environment["ROAM_MOCK_SEED"] == "1" {
                bootstrapMockSeed()
            }
            applyDebugNavIfNeeded()
            #endif
            await sync.pullAll()
        }
    }

    #if DEBUG
    private func applyDebugNavIfNeeded() {
        let nav = ProcessInfo.processInfo.environment["ROAM_NAV"] ?? ""
        let seedTripID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        switch nav {
        case "trip":
            path.append(Route.trip(seedTripID))
        case "expense":
            path.append(Route.trip(seedTripID))
            path.append(Route.newExpense(seedTripID))
        default:
            break
        }
    }

    private func bootstrapMockSeed() {
        guard let user = auth.currentUser else { return }
        let seedTripID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == seedTripID })
        guard (try? context.fetch(descriptor))?.isEmpty == true else { return }
        let anyaID = UUID(uuidString: "AAAAAAAA-0001-0000-0000-000000000000")!
        let samID  = UUID(uuidString: "AAAAAAAA-0002-0000-0000-000000000000")!

        if (try? context.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate<ProfileEntity> { $0.id == anyaID }
        )))?.isEmpty == true {
            context.insert(ProfileEntity(id: anyaID, displayName: "Anya"))
        }
        if (try? context.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate<ProfileEntity> { $0.id == samID }
        )))?.isEmpty == true {
            context.insert(ProfileEntity(id: samID, displayName: "Sam"))
        }

        let trip = TripEntity(id: seedTripID, name: "Lisbon w/ Anya & Sam", createdByID: user.id)
        trip.lastActivityAt = .now.addingTimeInterval(-86400 * 2)
        context.insert(trip)
        context.insert(TripMemberEntity(userID: user.id, trip: trip))
        context.insert(TripMemberEntity(userID: anyaID, trip: trip))
        context.insert(TripMemberEntity(userID: samID, trip: trip))

        addMockExpense(
            description: "Dinner at Ramiro",
            payerID: user.id, amount: 85, currency: "EUR",
            categoryID: DefaultCategories.food.id,
            participants: [user.id, anyaID, samID],
            daysAgo: 3, trip: trip
        )
        addMockExpense(
            description: "Uber to Sintra",
            payerID: anyaID, amount: Decimal(string: "22.40")!, currency: "EUR",
            categoryID: DefaultCategories.transport.id,
            participants: [user.id, anyaID, samID],
            daysAgo: 3, trip: trip
        )
        addMockExpense(
            description: "Airbnb (3 nights)",
            payerID: samID, amount: 420, currency: "EUR",
            categoryID: DefaultCategories.lodging.id,
            participants: [user.id, anyaID, samID],
            daysAgo: 5, trip: trip
        )

        try? context.save()
    }

    private func addMockExpense(
        description: String,
        payerID: UUID,
        amount: Decimal,
        currency: String,
        categoryID: UUID,
        participants: [UUID],
        daysAgo: Int,
        trip: TripEntity
    ) {
        let expense = ExpenseEntity(
            payerID: payerID,
            amount: amount,
            currency: currency,
            categoryID: categoryID,
            descriptionText: description,
            expenseDate: .now.addingTimeInterval(TimeInterval(-86400 * daysAgo)),
            createdByID: payerID,
            trip: trip
        )
        context.insert(expense)

        let cents = (amount as NSDecimalNumber).multiplying(by: 100).intValue
        let n = participants.count
        let base = cents / n
        let remainder = cents - base * n
        let sorted = participants.sorted { $0.uuidString < $1.uuidString }
        for (i, pid) in sorted.enumerated() {
            let owedCents = base + (i < remainder ? 1 : 0)
            let owed = Decimal(owedCents) / 100
            context.insert(ExpenseSplitEntity(
                userID: pid,
                amountOwed: owed,
                splitTypeRaw: "equal",
                expense: expense
            ))
        }
    }
    #endif

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
            let existingIDs = Set(existing.map(\.id))
            for def in DefaultCategories.all where !existingIDs.contains(def.id) {
                context.insert(CategoryEntity(
                    id: def.id, tripID: nil, name: def.name, icon: def.icon, isDefault: true
                ))
            }
            try context.save()
        } catch { }
    }
}

enum Route: Hashable {
    case trip(UUID)
    case newExpense(UUID)
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
            Text("Coming soon")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)

            if let email = auth.currentUser?.email {
                Text(email)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
                    .padding(.top, 6)
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
