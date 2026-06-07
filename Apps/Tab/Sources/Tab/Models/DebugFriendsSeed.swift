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
#endif
