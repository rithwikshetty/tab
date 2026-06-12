#if DEBUG
import Foundation
import SwiftData

/// Seeds trips + a non-group container with shared people and expenses so the Friends
/// tab and friend detail can be exercised under mock auth (real sync disabled). Gated
/// behind `TAB_SEED_FRIENDS=1`. Builds a multi-currency, multi-source picture:
///   • Sam: owes you €30 (Goa), you owe Sam £14 net (Tokyo £20 − non-group £6)
///   • Alex: owes you €30 (Goa)
///   • Jamie (pending invite): owes you £4 (non-group)
enum DebugFriendsSeed {
    static func seedIfRequested(in context: ModelContext, currentUserID: UUID?) {
        guard ProcessInfo.processInfo.environment["TAB_SEED_FRIENDS"] == "1" else { return }
        guard let me = currentUserID else { return }
        // Only seed an empty store so we don't duplicate on every launch.
        guard (try? context.fetch(FetchDescriptor<TripEntity>()))?.isEmpty == true else { return }

        let now = Date()
        let day = TimeInterval(86_400)

        func person(_ userID: UUID?, _ email: String, _ name: String, _ trip: TripEntity) -> TripPersonEntity {
            let w = UUID()
            let p = TripPersonEntity(
                id: UUID(), userID: userID, email: email, displayName: name,
                invitedByID: me, trip: trip, joinedAt: userID == nil ? nil : now,
                writeID: w, pushedWriteID: w
            )
            context.insert(p)
            return p
        }

        func expense(_ trip: TripEntity, _ amount: Decimal, _ currency: String, _ desc: String,
                     daysAgo: Double, payer: TripPersonEntity, splits: [(TripPersonEntity, Decimal)]) {
            let w = UUID()
            let e = ExpenseEntity(
                id: UUID(), amount: amount, currency: currency, categoryID: DefaultCategories.food.id,
                descriptionText: desc, expenseDate: now.addingTimeInterval(-daysAgo * day),
                createdByID: payer.userID ?? me, trip: trip,
                createdAt: now.addingTimeInterval(-daysAgo * day), writeID: w, pushedWriteID: w
            )
            context.insert(e)
            context.insert(PaymentEntity(tripPersonID: payer.id, amountPaid: amount, paymentModeRaw: "equal", expense: e))
            for (sp, owed) in splits {
                context.insert(ExpenseSplitEntity(tripPersonID: sp.id, amountOwed: owed, splitTypeRaw: "equal", expense: e))
            }
        }

        let samEmail = "sam@tab.local", alexEmail = "alex@tab.local", jamieEmail = "jamie@tab.local"
        let samUser = UUID(uuidString: "5A115A11-0000-0000-0000-000000000001")!
        let alexUser = UUID(uuidString: "A1EA1EA1-0000-0000-0000-000000000002")!

        func container(_ name: String, kind: String, signature: String?) -> TripEntity {
            let w = UUID()
            let t = TripEntity(
                id: UUID(), name: name, kind: kind, memberSignature: signature, createdByID: me,
                lastActivityAt: now, writeID: w, pushedWriteID: w
            )
            context.insert(t)
            return t
        }

        // Goa {me, Sam, Alex}: I paid €90, split 3 ways → Sam & Alex each owe me €30.
        let goa = container("Goa", kind: "trip", signature: nil)
        let goaMe = person(me, "mock@tab.local", "Me", goa)
        let goaSam = person(samUser, samEmail, "Sam", goa)
        let goaAlex = person(alexUser, alexEmail, "Alex", goa)
        expense(goa, 90, "EUR", "Beach villa", daysAgo: 5, payer: goaMe,
                splits: [(goaMe, 30), (goaSam, 30), (goaAlex, 30)])

        // Tokyo {me, Sam}: Sam paid £40, split 2 → I owe Sam £20.
        let tokyo = container("Tokyo", kind: "trip", signature: nil)
        let tokyoMe = person(me, "mock@tab.local", "Me", tokyo)
        let tokyoSam = person(samUser, samEmail, "Sam", tokyo)
        expense(tokyo, 40, "GBP", "Ramen", daysAgo: 12, payer: tokyoSam,
                splits: [(tokyoMe, 20), (tokyoSam, 20)])

        // Non-group {me, Sam}: I paid £12, split 2 → Sam owes me £6.
        let ngSam = container("", kind: "non_group", signature: "mock@tab.local|\(samEmail)")
        let ngSamMe = person(me, "mock@tab.local", "Me", ngSam)
        let ngSamSam = person(samUser, samEmail, "Sam", ngSam)
        expense(ngSam, 12, "GBP", "Drinks", daysAgo: 2, payer: ngSamMe,
                splits: [(ngSamMe, 6), (ngSamSam, 6)])

        // Non-group {me, Jamie pending}: I paid £8, split 2 → Jamie owes me £4.
        let ngJamie = container("", kind: "non_group", signature: "\(jamieEmail)|mock@tab.local")
        let ngJamieMe = person(me, "mock@tab.local", "Me", ngJamie)
        let ngJamieJ = person(nil, jamieEmail, "Jamie", ngJamie)
        expense(ngJamie, 8, "GBP", "Cab", daysAgo: 1, payer: ngJamieMe,
                splits: [(ngJamieMe, 4), (ngJamieJ, 4)])

        // Stress case for text layout: a long display name + a large THB amount, and
        // a second currency owed the other way, so the banner and rows must wrap/truncate.
        let thailand = container("Thailand 2026", kind: "trip", signature: nil)
        let thaiMe = person(me, "mock@tab.local", "Me", thailand)
        let thaiLong = person(nil,
                              "bartholomew@tab.local", "Bartholomew Featherstonehaugh-Wellington", thailand)
        // They paid THB 11,262.30 split 2 → I owe them THB 5,631.15.
        expense(thailand, 11262.30, "THB", "Resort", daysAgo: 9, payer: thaiLong,
                splits: [(thaiMe, 5631.15), (thaiLong, 5631.15)])
        // I paid €120 split 2 → they owe me €60 (multi-currency with a long name).
        expense(thailand, 120, "EUR", "Diving", daysAgo: 8, payer: thaiMe,
                splits: [(thaiMe, 60), (thaiLong, 60)])

        try? context.save()
    }
}

/// Seeds polished, realistic demo data for marketing screenshots under mock auth.
/// Gated behind `TAB_SEED_DEMO=1`. Three trips (EUR city break, JPY ski trip,
/// GBP flatshare), five friends, balanced multi-payer expenses across all
/// categories, a settlement, and a believable activity feed.
enum DemoScreenshotSeed {
    static func seedIfRequested(in context: ModelContext, currentUserID: UUID?) {
        guard ProcessInfo.processInfo.environment["TAB_SEED_DEMO"] == "1" else { return }
        guard let me = currentUserID else { return }
        guard (try? context.fetch(FetchDescriptor<TripEntity>()))?.isEmpty == true else { return }

        let now = Date()
        let day = TimeInterval(86_400)
        let hour = TimeInterval(3_600)

        func trip(_ name: String, lastActivity: Date) -> TripEntity {
            let w = UUID()
            let t = TripEntity(
                id: UUID(), name: name, kind: "trip", memberSignature: nil, createdByID: me,
                lastActivityAt: lastActivity, writeID: w, pushedWriteID: w
            )
            context.insert(t)
            return t
        }

        func person(_ userID: UUID?, _ email: String, _ name: String, _ trip: TripEntity) -> TripPersonEntity {
            let w = UUID()
            let p = TripPersonEntity(
                id: UUID(), userID: userID, email: email, displayName: name,
                invitedByID: me, trip: trip, joinedAt: userID == nil ? nil : now,
                writeID: w, pushedWriteID: w
            )
            context.insert(p)
            return p
        }

        func expense(_ trip: TripEntity, _ amount: Decimal, _ currency: String, _ desc: String,
                     category: UUID, daysAgo: Double, payer: TripPersonEntity,
                     among people: [TripPersonEntity], share: Decimal) {
            let w = UUID()
            let date = now.addingTimeInterval(-daysAgo * day)
            let e = ExpenseEntity(
                id: UUID(), amount: amount, currency: currency, categoryID: category,
                descriptionText: desc, expenseDate: date,
                createdByID: payer.userID ?? me, trip: trip,
                createdAt: date, writeID: w, pushedWriteID: w
            )
            context.insert(e)
            context.insert(PaymentEntity(tripPersonID: payer.id, amountPaid: amount, paymentModeRaw: "equal", expense: e))
            for sp in people {
                context.insert(ExpenseSplitEntity(tripPersonID: sp.id, amountOwed: share, splitTypeRaw: "equal", expense: e))
            }
        }

        func activity(_ trip: TripEntity, _ actorID: UUID, _ action: String, _ entityType: String,
                      hoursAgo: Double, _ snapshot: [String: String]) {
            var snap = snapshot
            snap["trip_name"] = trip.name
            context.insert(ActivityEntity(
                id: UUID(), tripID: trip.id, actorID: actorID, action: action,
                entityType: entityType, entityID: UUID(),
                timestamp: now.addingTimeInterval(-hoursAgo * hour),
                snapshotData: try? JSONEncoder().encode(snap)
            ))
        }

        let mayaID  = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000001")!
        let danID   = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000002")!
        let priyaID = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000003")!
        let tomID   = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000004")!
        let leoID   = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000005")!
        let anaID   = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000006")!
        let jessID  = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000007")!
        let omarID  = UUID(uuidString: "DEB0DEB0-0000-0000-0000-000000000008")!

        // ── Lisbon Long Weekend (EUR): me, Maya, Dan, Priya.
        let lisbon = trip("Lisbon Long Weekend", lastActivity: now.addingTimeInterval(-2 * hour))
        let liMe = person(me, "mock@tab.local", "You", lisbon)
        let liMaya = person(mayaID, "maya@tab.local", "Maya", lisbon)
        let liDan = person(danID, "dan@tab.local", "Dan", lisbon)
        let liPriya = person(priyaID, "priya@tab.local", "Priya", lisbon)
        let liAll = [liMe, liMaya, liDan, liPriya]
        expense(lisbon, 420.00, "EUR", "Airbnb in Alfama", category: DefaultCategories.lodging.id,
                daysAgo: 3.4, payer: liMe, among: liAll, share: 105.00)
        expense(lisbon, 140.00, "EUR", "Surf lesson, Caparica", category: DefaultCategories.activities.id,
                daysAgo: 2.3, payer: liMe, among: liAll, share: 35.00)
        expense(lisbon, 86.40, "EUR", "Dinner in Bairro Alto", category: DefaultCategories.food.id,
                daysAgo: 1.9, payer: liDan, among: liAll, share: 21.60)
        expense(lisbon, 25.20, "EUR", "Tram 28 day passes", category: DefaultCategories.transport.id,
                daysAgo: 1.2, payer: liMaya, among: liAll, share: 6.30)
        expense(lisbon, 12.80, "EUR", "Pastéis de Belém", category: DefaultCategories.food.id,
                daysAgo: 0.9, payer: liPriya, among: liAll, share: 3.20)
        context.insert(SettlementEntity(
            fromPersonID: liDan.id, toPersonID: liMe.id, amount: 60.00, currency: "EUR",
            note: "Revolut", settledAt: now.addingTimeInterval(-1.1 * day), createdByID: danID,
            trip: lisbon
        ))

        // ── Japan Ski Cabin (JPY): me, Tom, Maya, Leo, Ana.
        let japan = trip("Japan Ski Cabin", lastActivity: now.addingTimeInterval(-19 * day))
        let jpMe = person(me, "mock@tab.local", "You", japan)
        let jpTom = person(tomID, "tom@tab.local", "Tom", japan)
        let jpMaya = person(mayaID, "maya@tab.local", "Maya", japan)
        let jpLeo = person(leoID, "leo@tab.local", "Leo", japan)
        let jpAna = person(anaID, "ana@tab.local", "Ana", japan)
        let jpAll = [jpMe, jpTom, jpMaya, jpLeo, jpAna]
        expense(japan, 182_000, "JPY", "Cabin in Niseko", category: DefaultCategories.lodging.id,
                daysAgo: 24, payer: jpTom, among: jpAll, share: 36_400)
        expense(japan, 58_500, "JPY", "Lift passes", category: DefaultCategories.activities.id,
                daysAgo: 23, payer: jpMe, among: jpAll, share: 11_700)
        expense(japan, 31_200, "JPY", "Snow gear rental", category: DefaultCategories.shopping.id,
                daysAgo: 22.5, payer: jpAna, among: jpAll, share: 6_240)
        expense(japan, 23_400, "JPY", "Izakaya night", category: DefaultCategories.food.id,
                daysAgo: 21.8, payer: jpLeo, among: jpAll, share: 4_680)

        // ── Flat 23 (GBP): me, Jess, Omar.
        let flat = trip("Flat 23", lastActivity: now.addingTimeInterval(-7 * hour))
        let flMe = person(me, "mock@tab.local", "You", flat)
        let flJess = person(jessID, "jess@tab.local", "Jess", flat)
        let flOmar = person(omarID, "omar@tab.local", "Omar", flat)
        let flAll = [flMe, flJess, flOmar]
        expense(flat, 64.20, "GBP", "Big shop", category: DefaultCategories.food.id,
                daysAgo: 0.3, payer: flJess, among: flAll, share: 21.40)
        expense(flat, 33.00, "GBP", "Internet", category: DefaultCategories.other.id,
                daysAgo: 4.0, payer: flMe, among: flAll, share: 11.00)
        expense(flat, 18.75, "GBP", "Cleaning supplies", category: DefaultCategories.shopping.id,
                daysAgo: 5.5, payer: flOmar, among: flAll, share: 6.25)

        // ── Activity feed.
        activity(lisbon, mayaID, "expense_created", "expense", hoursAgo: 2,
                 ["actor_name": "Maya", "description": "Tram 28 day passes", "amount": "25.20", "currency": "EUR"])
        activity(flat, jessID, "expense_created", "expense", hoursAgo: 7,
                 ["actor_name": "Jess", "description": "Big shop", "amount": "64.20", "currency": "GBP"])
        activity(lisbon, priyaID, "expense_created", "expense", hoursAgo: 22,
                 ["actor_name": "Priya", "description": "Pastéis de Belém", "amount": "12.80", "currency": "EUR"])
        activity(lisbon, danID, "settlement_created", "settlement", hoursAgo: 26,
                 ["actor_name": "Dan", "from_name": "Dan", "to_name": "You", "amount": "60.00", "currency": "EUR"])
        activity(lisbon, danID, "expense_created", "expense", hoursAgo: 46,
                 ["actor_name": "Dan", "description": "Dinner in Bairro Alto", "amount": "86.40", "currency": "EUR"])
        activity(japan, anaID, "member_joined", "member", hoursAgo: 600,
                 ["actor_name": "Tom", "member_name": "Ana"])

        try? context.save()
    }
}
#endif
